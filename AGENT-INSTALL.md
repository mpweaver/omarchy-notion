# Agent installation guide

This guide is for an LLM or automation agent installing Omarchy Notion Capture for a user. Do not request, echo, log, commit, or persist the user's Notion installation access token.

## Outcome

After setup, the user has:

- `user.omarchy-notion` enabled in the Omarchy bar
- `notion` and `omarchy-notion` commands in `~/.local/bin`
- a dedicated Notion database named **Omarchy**
- a Notion token stored only in the desktop keyring

## 1. Preflight

Run read-only checks:

```bash
command -v omarchy
omarchy version
command -v git
```

Stop if this is not an Omarchy system. Never reuse another person's `~/.config/omarchy-notion/config.json`, database IDs, page IDs, or keyring entry.

## 2. Install the widget

With the user's approval for repository installation:

```bash
omarchy plugin add https://github.com/mpweaver/omarchy-notion --enable --yes
omarchy bar move user.omarchy-notion --section right
```

This is the standard Omarchy plugin flow and installs the repository into `~/.config/omarchy/plugins/user.omarchy-notion`.

## 3. Enable the terminal CLI

Omarchy does not run plugin install hooks. With the user's approval for package installation, run:

```bash
bash ~/.config/omarchy/plugins/user.omarchy-notion/install.sh
```

The setup adds `curl`, `jq`, `libsecret`, and `wl-clipboard` through Omarchy and creates the `notion` and `omarchy-notion` command links.

## 4. Create the Notion connection

This step requires the user to work in their signed-in Notion account:

1. Open <https://www.notion.so/profile/integrations>.
2. Create a connection named **Omarchy Notion Capture**.
3. Select the user's intended workspace.
4. Enable **Insert content**. No user-information or comment capability is required.
5. Copy the installation access token.
6. Create or choose a normal Notion page that will contain the database.
7. From that page's menu, open **Connections** and add **Omarchy Notion Capture**.
8. Copy the shared page URL.

Do not ask the user to paste the token into chat, a command argument, a file, or an agent tool call.

## 5. Run secure setup

Launch the interactive wizard in a user-controlled terminal:

```bash
xdg-terminal-exec --hold notion setup
```

The user—not the agent—must paste the token into the hidden prompt and then enter the shared parent-page URL. The wizard stores the token with `secret-tool`, creates the **Omarchy** database, and saves only the generated IDs and URL in `~/.config/omarchy-notion/config.json` with user-only permissions.

## 6. Verify

After the user completes the wizard:

```bash
notion status | jq -e '.configured == true and .has_token == true'
notion -t "Omarchy setup test" -b "Widget and CLI installation succeeded." -h setup -s Agent
```

Ask the user to confirm that the test page appears in the **Omarchy** database. Then verify the bar widget opens, accepts text, and shows **Ready to capture**.

For PNG verification, the user may copy a PNG and run:

```bash
notion -t "PNG setup test" -b "Clipboard attachment test" -h setup -i
```

The maximum PNG size is 20 MB.

## 7. Agent captures

Prefer JSON over shell-constructed arguments:

```bash
printf '%s' '{"title":"Agent note","body":"Work completed","tags":["agent"],"source":"Agent"}' \
  | notion capture --json
```

For an existing PNG file:

```bash
jq -cn \
  --arg title "Agent screenshot" \
  --arg body "Captured during agent work" \
  --arg image_path "/absolute/path/to/image.png" \
  '{title:$title,body:$body,tags:["agent"],source:"Agent",image_path:$image_path}' \
  | notion capture --json
```

The CLI validates that the attachment is a PNG no larger than 20 MB. It preserves agent-supplied files by default.

## Security boundaries

- Never read or print the keyring token.
- Never copy `~/.config/omarchy-notion` from another machine or user.
- Never add generated configuration, cached clipboard PNGs, or secrets to the plugin repository.
- Do not create or change Notion resources outside the shared parent page without explicit user authorization.
- Report setup errors without including authorization headers or tokens.
