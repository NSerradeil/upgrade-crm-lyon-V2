# Guide : Accéder à tes MCP Servers depuis ton iPhone

## Architecture

```
iPhone (Claude.ai / app MCP)
    │
    ▼ (VPN Tailscale - chiffré)
    │
Mac Mini / MacBook
    ├── mcp-proxy (SSE sur port 8080)
    │     ├── Obsidian MCP Server
    │     ├── Filesystem MCP (Plaud transcriptions)
    │     ├── Supabase MCP (CRM Lyon)
    │     └── Autres MCP servers...
```

---

## Etape 1 : Installer Tailscale

### Sur ton Mac

```bash
# Via Homebrew
brew install --cask tailscale

# OU télécharger depuis https://tailscale.com/download/mac
```

Lancer Tailscale, se connecter avec Google/GitHub/Apple.

### Sur ton iPhone

1. Télécharger **Tailscale** sur l'App Store (gratuit)
2. Se connecter avec le **même compte** que sur le Mac
3. Les deux appareils apparaissent dans ton réseau Tailscale

### Vérifier la connexion

```bash
# Sur ton Mac, voir les appareils connectés
tailscale status

# Tu verras quelque chose comme :
# 100.x.x.1  macbook     tag:personal
# 100.x.x.2  iphone      tag:personal
```

Note ton **IP Tailscale du Mac** (ex: `100.64.0.1`), tu en auras besoin.

---

## Etape 2 : Installer les MCP Servers sur ton Mac

### 2a. Obsidian MCP Server

```bash
# Installer le serveur Obsidian
npm install -g @anthropic/mcp-server-obsidian
# OU
npm install -g obsidian-mcp-server
```

### 2b. Filesystem MCP (pour Plaud et autres fichiers)

```bash
npm install -g @anthropic/mcp-server-filesystem
```

### 2c. Supabase MCP (pour le CRM)

```bash
npm install -g @supabase/mcp-server
```

---

## Etape 3 : Installer et configurer mcp-proxy

### Installation

```bash
pip install mcp-proxy
# OU
pipx install mcp-proxy
```

### Créer le fichier de config MCP

Créer le fichier `~/.mcp-servers.json` :

```json
{
  "mcpServers": {
    "obsidian": {
      "command": "npx",
      "args": ["-y", "obsidian-mcp-server", "--vault", "/Users/TON_USER/Documents/ObsidianVault"]
    },
    "filesystem-plaud": {
      "command": "npx",
      "args": [
        "-y",
        "@anthropic/mcp-server-filesystem",
        "/Users/TON_USER/Documents/Plaud"
      ]
    },
    "filesystem-general": {
      "command": "npx",
      "args": [
        "-y",
        "@anthropic/mcp-server-filesystem",
        "/Users/TON_USER/Documents"
      ]
    },
    "supabase-crm": {
      "command": "npx",
      "args": ["-y", "@supabase/mcp-server"],
      "env": {
        "SUPABASE_URL": "https://ehfseahxoivfhmpiyoqa.supabase.co",
        "SUPABASE_SERVICE_ROLE_KEY": "TA_SERVICE_ROLE_KEY_ICI"
      }
    }
  }
}
```

> **IMPORTANT** : Remplacer `TON_USER` par ton nom d'utilisateur Mac et les chemins par les vrais chemins de tes dossiers.

---

## Etape 4 : Lancer le proxy MCP

### Lancement manuel

```bash
# Lancer le proxy SSE accessible via Tailscale
mcp-proxy --sse-port 8080 --host 0.0.0.0 --config ~/.mcp-servers.json
```

### Script de lancement automatique

Créer `~/start-mcp-remote.sh` :

```bash
#!/bin/bash
echo "Demarrage du proxy MCP sur port 8080..."
echo "Accessible via Tailscale sur $(tailscale ip -4):8080"
mcp-proxy --sse-port 8080 --host 0.0.0.0 --config ~/.mcp-servers.json
```

```bash
chmod +x ~/start-mcp-remote.sh
```

### Lancement automatique au démarrage (optionnel)

Créer `~/Library/LaunchAgents/com.mcp-proxy.plist` :

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.mcp-proxy</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>/Users/TON_USER/start-mcp-remote.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/mcp-proxy.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/mcp-proxy-error.log</string>
</dict>
</plist>
```

```bash
launchctl load ~/Library/LaunchAgents/com.mcp-proxy.plist
```

---

## Etape 5 : Utiliser depuis ton iPhone

### Option A : Claude Desktop (si dispo sur iOS)

Dans les settings MCP de Claude, ajouter un serveur remote :

```
URL: http://100.x.x.x:8080/sse
```

(Remplacer `100.x.x.x` par l'IP Tailscale de ton Mac)

### Option B : Claude.ai sur Safari

Tu peux utiliser Claude.ai en web et configurer des MCP servers remote dans les paramètres du projet.

### Option C : App MCP tierce

Des apps comme **MCP Chat** ou **Cursor Mobile** (si disponibles) peuvent se connecter à un endpoint SSE.

---

## Etape 6 : Tester

Depuis ton iPhone (connecté à Tailscale) :

1. Ouvrir Safari et aller sur `http://100.x.x.x:8080/sse` - tu dois voir une connexion SSE active
2. Dans Claude, tester une commande comme "Liste mes notes Obsidian"
3. Tester "Récupère mes dernières transcriptions Plaud"

---

## Sécurité

- **Tailscale** chiffre tout le trafic entre tes appareils (WireGuard)
- Le port 8080 n'est **PAS exposé sur internet**, uniquement accessible via le VPN Tailscale
- Pour plus de sécurité, tu peux ajouter une authentification au proxy :

```bash
# Avec un token d'authentification
mcp-proxy --sse-port 8080 --host 0.0.0.0 --auth-token "MON_TOKEN_SECRET" --config ~/.mcp-servers.json
```

---

## Dépannage

| Problème | Solution |
|---|---|
| iPhone ne voit pas le Mac | Vérifier que Tailscale est actif sur les 2 appareils |
| Connexion refusée sur :8080 | Vérifier que mcp-proxy tourne (`ps aux \| grep mcp-proxy`) |
| MCP server crash | Vérifier les logs : `cat /tmp/mcp-proxy-error.log` |
| Obsidian vault pas trouvé | Vérifier le chemin dans `~/.mcp-servers.json` |

---

## Résumé des commandes

```bash
# Installation (une seule fois)
brew install --cask tailscale
pip install mcp-proxy
npm install -g @anthropic/mcp-server-filesystem

# Lancement quotidien
~/start-mcp-remote.sh

# Vérification
tailscale status
curl http://localhost:8080/sse
```
