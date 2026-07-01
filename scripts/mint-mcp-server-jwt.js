// Myntar en långlivad JWT för den begränsade "mcp_server"-rollen.
// Körs lokalt EN gång — resultatet klistras in i mcp_promptbanken/.env
// på VPS:en som SUPABASE_SERVICE_ROLE_KEY (ersätter den riktiga
// service-role-nyckeln). Kräver SUPABASE_JWT_SECRET (Dashboard →
// Settings → API → JWT Secret). Körs aldrig i produktion, aldrig i Git.
//
// Användning:
//   SUPABASE_JWT_SECRET=... node scripts/mint-mcp-server-jwt.js

import jwt from "jsonwebtoken";

const secret = process.env.SUPABASE_JWT_SECRET;
if (!secret) {
  console.error("SUPABASE_JWT_SECRET saknas. Sätt den som env-variabel innan körning.");
  process.exit(1);
}

const token = jwt.sign(
  { role: "mcp_server", iss: "supabase" },
  secret,
  { algorithm: "HS256" }
);

console.log(token);
