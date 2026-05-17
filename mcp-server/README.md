# Promptbanken MCP Server

Minimal MCP-server som exponerar Promptbankens promptar som skills.

## Starta lokalt

```powershell
npm run setup:python
npm run dev
```

`npm run dev` startar en MCP stdio-server. Den ser normalt ut att vanta eftersom MCP-klienten kommunicerar via standard input/output.

## MCP-konfiguration

```json
{
  "mcpServers": {
    "promptbanken": {
      "command": "npm",
      "args": ["run", "--silent", "dev"],
      "cwd": "C:\\path\\to\\promptbanken\\mcp-server"
    }
  }
}
```

## Tools

- `list_skills`
- `get_skill`
- `route_skill`
- `compile_skill_prompt`
- `check_input_risk`

## Filer som behovs

- `skills.json`
- `prompts/*.txt`
- `server/*.py`
- `scripts/*.js`
- `requirements.txt`
- `package.json`
