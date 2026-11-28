# エージェントプラグイン（cursor-team-kit / pstack）運用メモ

## 1. 方針と初回セットアップ

**プラグイン本体はリポジトリにコミットしない**（`.gitignore` 済み、`node_modules` と同じ運用）。

```bash
bash .agents/plugins/install-cursor-plugins.sh
```

- 上流 (`cursor/plugins`) から sparse clone して `.agents/plugins/` へ `rsync --delete` で展開する。更新も同じコマンドの再実行で行う。
- 導入プラグイン:
  - **cursor-team-kit**: 18 スキル + 2 サブエージェント（`deslop` / `verify-this` / `loop-on-ci` / `control-ui` 等）
  - **pstack**: 59 スキル + 2 サブエージェント（`/pstack:poteto-mode` が中心。参照する `cursor-team-kit` の `/deslop` / `control-ui` / `control-cli` は同時導入で満たされる）
- スクリプトは本体展開に加えて、`.devin/config.json`（gitignore 済みのローカルファイル）の `requiredPlugins` へローカル相対パスを自動登録・マージする。

## 2. `install-cursor-plugins.sh` が行う上流からの変換

- `.cursor-plugin/` 除外
- `assets/avatar.png` / `logo.png` → `icon.png` リネーム
- `agents/*.md` から非ポータブルな `model:` / `is_background:` 行を除去
- `cursor-team-kit` の root `plugin.json` を上流 `.cursor-plugin/plugin.json` から `jq` で変換生成（Cursor 固有キーを落とし、他メタデータは継承）

## 3. Devin 向けの検証済み事実と adapter

- `.devin/config.json` の `requiredPlugins` にローカル相対パス（例: `"./.agents/plugins/cursor-team-kit"`）を書くと認証不要で読み込まれる。
- `.agents/plugins/marketplace.json` は Devin に自動ロードされない（OpenAI/Codex の規約）。
- 検証コマンド（認証不要）:
  ```bash
  devin skills list
  # discovery ログで active_plugins=2 skills=77 agents=4 を確認
  ```
- `devin plugins install/list` はクラウド認証 (`devin auth login`) が必須だが、repo レベルの `requiredPlugins` 解決には不要。
- pstack のスキルは `disable-model-invocation` 付きが多く、`/pstack:<skill>` で明示起動する設計（Devin 一覧では `[user]` 表示）。サブエージェントは CLI / Devin Desktop のみでロードされる。
- **Devin 専用 adapter (`/devin-poteto-mode`)**:
  - `.agents/skills/devin-poteto-mode/SKILL.md` — `pstack:poteto-mode` 本体は複製せず、`Task` → `run_subagent`、`subagent_type` → `profile`、`run_in_background` → `is_background` および `.devin/agents/poteto-swe-write.md` / `poteto-swe-review.md` (`model: swe-2-1-high`) への対応表のみを持つ。
  - 検証: `bash .agents/skills/devin-poteto-mode/validate.sh`。
  - custom subagent profile はセッション開始時に読み込まれるため、`Unknown subagent profile` が出たら新しい Devin セッションで確認する。

## 4. Antigravity 向け adapter

- `.agents/skills/gemini-poteto-mode/SKILL.md` — Antigravity 用の `poteto-mode` adapter。
