// Supabase Edge Function: self-service account deletion.
//
// Körs med service-role-behörighet (SUPABASE_SERVICE_ROLE_KEY injiceras
// automatiskt av Supabase Functions-runtimen). Anropas av den inloggade
// användaren själv för att permanent radera sitt konto.
//
// Flöde:
// 1. Verifiera anropande användares JWT och läs ut user_id.
// 2. Om användaren äger en organisation med andra medlemmar: blockera
//    (måste överföra ägarskap innan konto kan raderas).
// 3. Radera personliga/tomma organisations-workspaces användaren äger.
//    (workspaces.owner_user_id har "on delete restrict" mot auth.users,
//    så workspacet måste bort innan auth.users-raden kan raderas.)
//    content_items/api_keys/profiles för workspacet cascadas bort
//    automatiskt via workspace_id-foreign keys.
// 4. Radera själva auth.users-raden via Admin API.

import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return jsonResponse({ error: "Saknar Authorization-header." }, 401);
  }

  const jwt = authHeader.replace("Bearer ", "");

  // Klient scopead till anroparens egen JWT - används bara för att
  // identifiera vem som ringer, inte för privilegierade operationer.
  const callerClient = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    global: { headers: { Authorization: authHeader } },
  });

  const { data: userData, error: userError } = await callerClient.auth.getUser(jwt);
  if (userError || !userData?.user) {
    return jsonResponse({ error: "Ogiltig session." }, 401);
  }

  const userId = userData.user.id;

  // Admin-klient (service role) för privilegierade operationer.
  const adminClient = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  const { data: ownedWorkspaces, error: workspacesError } = await adminClient
    .from("workspaces")
    .select("id, type")
    .eq("owner_user_id", userId);

  if (workspacesError) {
    return jsonResponse({ error: "Kunde inte slå upp workspaces." }, 500);
  }

  for (const workspace of ownedWorkspaces ?? []) {
    if (workspace.type === "organization") {
      const { count, error: memberError } = await adminClient
        .from("profiles")
        .select("user_id", { count: "exact", head: true })
        .eq("workspace_id", workspace.id)
        .neq("user_id", userId);

      if (memberError) {
        return jsonResponse({ error: "Kunde inte kontrollera organisationsmedlemmar." }, 500);
      }

      if ((count ?? 0) > 0) {
        return jsonResponse(
          {
            error:
              "Du äger en organisation med andra medlemmar. Överför ägarskapet innan du kan radera ditt konto.",
          },
          409,
        );
      }
    }

    const { error: deleteWorkspaceError } = await adminClient
      .from("workspaces")
      .delete()
      .eq("id", workspace.id);

    if (deleteWorkspaceError) {
      return jsonResponse({ error: "Kunde inte radera workspace." }, 500);
    }
  }

  const { error: deleteUserError } = await adminClient.auth.admin.deleteUser(userId);
  if (deleteUserError) {
    return jsonResponse({ error: deleteUserError.message || "Kunde inte radera kontot." }, 500);
  }

  return jsonResponse({ success: true }, 200);
});
