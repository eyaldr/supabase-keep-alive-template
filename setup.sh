#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  setup.sh — Supabase Keep-Alive interactive setup
#  יוצר workflow מותאם אישית ומגדיר secrets ב-GitHub
# ─────────────────────────────────────────────────────────────
set -uo pipefail

# ── colors ────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

ok()   { echo -e "${GREEN}  ✅ $*${NC}"; }
warn() { echo -e "${YELLOW}  ⚠️  $*${NC}"; }
err()  { echo -e "${RED}  ❌ $*${NC}"; exit 1; }
info() { echo -e "${BLUE}  ℹ️  $*${NC}"; }
hdr()  { echo -e "\n${BOLD}── $* ──────────────────────────────────────${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKFLOW="$SCRIPT_DIR/.github/workflows/supabase-keep-alive.yml"

# ── data ──────────────────────────────────────────────────────
declare -a NAMES=() URLS=() KEYS=() PREFIXES=()
EMAIL_ON=false; GMAIL_USER=""; GMAIL_PASS=""

# ── helpers ───────────────────────────────────────────────────
to_prefix() { echo "$1" | tr '[:lower:]' '[:upper:]' | tr ' -' '_' | tr -cd 'A-Z0-9_'; }
valid_name() { [[ "$1" =~ ^[A-Za-z][A-Za-z0-9\ _-]{0,29}$ ]]; }
valid_url()  { [[ "$1" =~ ^https://[a-z0-9]+\.supabase\.co$ ]]; }
valid_key()  { [[ "$1" =~ ^eyJ ]]; }

# ─────────────────────────────────────────────────────────────
#  1. Check / install gh CLI
# ─────────────────────────────────────────────────────────────
check_gh() {
  hdr "בדיקות מוקדמות"

  if ! command -v gh &>/dev/null; then
    warn "gh CLI לא מותקן."
    if [[ "$OSTYPE" == "darwin"* ]] && command -v brew &>/dev/null; then
      read -rp "  להתקין עם Homebrew? (y/n): " a
      if [[ "$a" == "y" ]]; then
        brew install gh || err "התקנת gh נכשלה"
      else
        err "נדרש gh CLI — התקן מ: https://cli.github.com ואז הרץ שוב."
      fi
    else
      echo "  התקן gh CLI מ: https://cli.github.com ואז הרץ שוב."
      exit 1
    fi
  fi
  ok "gh CLI ($(gh --version | head -1))"

  if ! gh auth status &>/dev/null; then
    info "נדרש חיבור ל-GitHub:"
    gh auth login || err "חיבור ל-GitHub נכשל"
  fi
  ok "GitHub: $(gh api user -q .login 2>/dev/null || echo 'connected')"
}

# ─────────────────────────────────────────────────────────────
#  2. Collect project info
# ─────────────────────────────────────────────────────────────
collect_projects() {
  hdr "פרויקטים"

  local count
  while true; do
    read -rp "  כמה פרויקטים Supabase? (1–4): " count
    [[ "$count" =~ ^[1-4]$ ]] && break
    warn "הזן מספר בין 1 ל-4"
  done

  for ((i=1; i<=count; i++)); do
    echo -e "\n  ${BOLD}פרויקט $i / $count:${NC}"
    local name url key

    # Name
    while true; do
      read -rp "    שם: " name
      if ! valid_name "$name"; then
        warn "שם לא תקין (אותיות, מספרים, רווח, מקף, קו-תחתון)"
        continue
      fi
      local dup=false
      if [[ ${#NAMES[@]} -gt 0 ]]; then
        for x in "${NAMES[@]}"; do [[ "$x" == "$name" ]] && dup=true && break; done
      fi
      if [[ "$dup" == "true" ]]; then warn "שם כבר בשימוש"; continue; fi
      break
    done

    # URL
    while true; do
      read -rp "    URL (https://xxxx.supabase.co): " url
      valid_url "$url" && break
      warn "URL לא תקין — חייב להתחיל ב-https:// ולהסתיים ב-.supabase.co"
    done

    # Anon key (hidden input)
    while true; do
      read -rsp "    Anon key (eyJ...): " key; echo ""
      valid_key "$key" && break
      warn "Key לא תקין — חייב להתחיל ב-eyJ"
    done

    NAMES+=("$name"); URLS+=("$url"); KEYS+=("$key")
    PREFIXES+=("$(to_prefix "$name")")
    ok "$name → secrets: $(to_prefix "$name")_URL + $(to_prefix "$name")_K"
  done
}

# ─────────────────────────────────────────────────────────────
#  3. Email settings
# ─────────────────────────────────────────────────────────────
collect_email() {
  hdr "דוחות מייל"
  read -rp "  להפעיל דוחות מייל? (y/n): " a
  if [[ "$a" != "y" ]]; then
    info "דוחות מייל מושבתים — ניתן להפעיל אח\"כ ב-workflow"
    return
  fi
  EMAIL_ON=true
  read -rp "    Gmail address: " GMAIL_USER
  read -rsp "    App Password (16 תווים): " GMAIL_PASS; echo ""
  ok "Gmail: $GMAIL_USER"
}

# ─────────────────────────────────────────────────────────────
#  4. Generate workflow YAML
#
#  Strategy: single-quoted heredoc for static boilerplate (no expansion),
#  unquoted heredoc for ping steps (need $nm/$pf expansion + \$ escapes
#  for GitHub expressions that must appear literally in the output),
#  printf for dynamic multi-project sections.
# ─────────────────────────────────────────────────────────────
gen_workflow() {
  local n=${#NAMES[@]}

  # Static header — single-quoted, no variable expansion
  cat > "$WORKFLOW" << 'YAML'
name: Supabase Keep-Alive

# קובץ זה נוצר אוטומטית ע"י setup.sh

on:
  schedule:
    - cron: "0 8 * * 1,3" # ב' + ד' ב-08:00 UTC (11:00 ישראל)
  workflow_dispatch:

jobs:
  ping:
    name: Ping all Supabase projects
    runs-on: ubuntu-latest
    steps:
YAML

  # One ping step per project
  # Unquoted heredoc: $nm/$pf expand at generation time; \${{ and \$ escape
  # literal $ signs that must survive into the YAML output.
  for ((i=1; i<=n; i++)); do
    local nm="${NAMES[$((i-1))]}" pf="${PREFIXES[$((i-1))]}"
    cat >> "$WORKFLOW" << STEP

      # ── ${nm} ──────────────────────────────────────────
      - name: Ping ${nm}
        id: p${i}
        continue-on-error: true
        run: |
          STATUS=\$(curl -s -o /dev/null -w "%{http_code}" \\
            "\${{ secrets.${pf}_URL }}/rest/v1/keep_alive?select=id&limit=1" \\
            -H "apikey: \${{ secrets.${pf}_K }}" \\
            -H "Authorization: Bearer \${{ secrets.${pf}_K }}")
          echo "status=\$STATUS" >> \$GITHUB_OUTPUT
          [ "\$STATUS" = "200" ] || exit 1
STEP
  done

  # Summary step — built with printf so we can loop over project names/IDs.
  # \$ in printf → literal $ in output.
  # %% in printf → literal % in output.
  {
    printf "\n      # ── סיכום ────────────────────────────────────────\n"
    printf "      - name: Write job summary\n"
    printf "        if: always()\n"
    printf "        run: |\n"
    for ((i=1; i<=n; i++)); do
      printf "          R%d=\"\${{ steps.p%d.outcome == 'success' && '✅ Alive' || '❌ Failed' }}\"\n" "$i" "$i"
    done
    printf "\n"
    printf "          cat >> \$GITHUB_STEP_SUMMARY << EOF\n"
    printf "          ## Supabase Keep-Alive Report\n"
    printf "          **Run time:** \$(date -u '+%%Y-%%m-%%d %%H:%%M UTC')\n"
    printf "\n"
    printf "          | Project | Status | HTTP |\n"
    printf "          |---------|--------|------|\n"
    for ((i=1; i<=n; i++)); do
      printf "          | %s | \$R%d | \${{ steps.p%d.outputs.status }} |\n" \
        "${NAMES[$((i-1))]}" "$i" "$i"
    done
    printf "          EOF\n"
  } >> "$WORKFLOW"

  # Email step (optional)
  if [[ "$EMAIL_ON" == "true" ]]; then
    local fail_cond=""
    for ((i=1; i<=n; i++)); do
      [[ -n "$fail_cond" ]] && fail_cond+=" || "
      fail_cond+="steps.p${i}.outcome == 'failure'"
    done

    {
      printf "\n      # ── מייל ──────────────────────────────────────────\n"
      printf "      - name: Send email report\n"
      printf "        if: always()\n"
      printf "        uses: dawidd6/action-send-mail@v4\n"
      printf "        with:\n"
      printf "          server_address: smtp.gmail.com\n"
      printf "          server_port: 465\n"
      printf "          username: \${{ secrets.GMAIL_USERNAME }}\n"
      printf "          password: \${{ secrets.GMAIL_APP_PASSWORD }}\n"
      printf "          to: \${{ secrets.GMAIL_USERNAME }}\n"
      printf "          from: Supabase Keep-Alive\n"
      printf "          subject: >\n"
      printf "            \${{ (%s)\n" "$fail_cond"
      printf "                && 'Supabase Keep-Alive - FAILED' || 'Supabase Keep-Alive - OK' }}\n"
      printf "          body: |\n"
      printf "            Supabase Keep-Alive Report\n"
      printf "            Run time: \${{ github.event.head_commit.timestamp || 'manual trigger' }}\n"
      printf "\n"
      for ((i=1; i<=n; i++)); do
        printf "            %s: \${{ steps.p%d.outcome == 'success' && 'Alive (200)' || 'FAILED' }}\n" \
          "${NAMES[$((i-1))]}" "$i"
      done
      printf "\n"
      printf "            Full report: https://github.com/\${{ github.repository }}/actions/runs/\${{ github.run_id }}\n"
    } >> "$WORKFLOW"
  fi

  # Fail step
  {
    printf "\n      # ── כשל כללי ─────────────────────────────────────\n"
    printf "      - name: Fail if any project is down\n"
    printf "        if: |\n"
    for ((i=1; i<=n; i++)); do
      if ((i < n)); then
        printf "          steps.p%d.outcome == 'failure' ||\n" "$i"
      else
        printf "          steps.p%d.outcome == 'failure'\n" "$i"
      fi
    done
    printf "        run: |\n"
    printf "          echo \"One or more Supabase projects failed the health check\"\n"
    printf "          exit 1\n"
  } >> "$WORKFLOW"
}

# ─────────────────────────────────────────────────────────────
#  5. secrets-checklist.txt (names only, no values)
# ─────────────────────────────────────────────────────────────
gen_checklist() {
  local f="$SCRIPT_DIR/secrets-checklist.txt"
  {
    printf "# Secrets שהוגדרו ע\"י setup.sh\n"
    printf "# לעיון בלבד — אין ערכים אמיתיים כאן\n\n"
    for ((i=0; i<${#NAMES[@]}; i++)); do
      printf "# ── %s ──\n%s_URL\n%s_K\n\n" "${NAMES[$i]}" "${PREFIXES[$i]}" "${PREFIXES[$i]}"
    done
    if [[ "$EMAIL_ON" == "true" ]]; then
      printf "# ── Gmail ──\nGMAIL_USERNAME\nGMAIL_APP_PASSWORD\n"
    fi
  } > "$f"
}

# ─────────────────────────────────────────────────────────────
#  6. .gitignore — keep secrets-checklist out of version control
# ─────────────────────────────────────────────────────────────
update_gitignore() {
  local gi="$SCRIPT_DIR/.gitignore"
  if ! grep -qx "secrets-checklist.txt" "$gi" 2>/dev/null; then
    echo "secrets-checklist.txt" >> "$gi"
  fi
}

# ─────────────────────────────────────────────────────────────
#  7. Set secrets via gh CLI
# ─────────────────────────────────────────────────────────────
set_secrets() {
  hdr "הגדרת secrets ב-GitHub"
  read -rp "  להגדיר secrets עכשיו? (y/n): " a
  if [[ "$a" != "y" ]]; then
    info "הגדר ידנית לפי secrets-checklist.txt"
    return
  fi

  local repo
  repo=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null) || {
    warn "לא נמצא GitHub remote — הגדר secrets ידנית."
    return
  }

  for ((i=0; i<${#NAMES[@]}; i++)); do
    gh secret set "${PREFIXES[$i]}_URL" --body "${URLS[$i]}"  --repo "$repo" && ok "${PREFIXES[$i]}_URL"
    gh secret set "${PREFIXES[$i]}_K"   --body "${KEYS[$i]}"  --repo "$repo" && ok "${PREFIXES[$i]}_K"
  done

  if [[ "$EMAIL_ON" == "true" ]]; then
    gh secret set "GMAIL_USERNAME"      --body "$GMAIL_USER" --repo "$repo" && ok "GMAIL_USERNAME"
    gh secret set "GMAIL_APP_PASSWORD"  --body "$GMAIL_PASS" --repo "$repo" && ok "GMAIL_APP_PASSWORD"
  fi
}

# ─────────────────────────────────────────────────────────────
#  8. Print SQL + next steps
# ─────────────────────────────────────────────────────────────
print_next_steps() {
  echo ""
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BOLD}  הרץ ב-Supabase SQL Editor (כל פרויקט בנפרד):${NC}"
  echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

  for ((i=0; i<${#NAMES[@]}; i++)); do
    echo -e "\n${YELLOW}-- ${NAMES[$i]}${NC}"
    cat << 'SQL'
create table if not exists keep_alive (id serial primary key, last_ping timestamptz default now());
insert into keep_alive default values;
alter table keep_alive enable row level security;
create policy "allow_anon_select" on keep_alive for select to anon using (true);
SQL
  done

  echo ""
  echo -e "${BOLD}לאחר הרצת ה-SQL:${NC}"
  echo "  GitHub → Actions → Supabase Keep-Alive → Run workflow → Run workflow"
  echo ""
}

# ─────────────────────────────────────────────────────────────
#  main
# ─────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}      Supabase Keep-Alive — הגדרה אוטומטית          ${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

check_gh
collect_projects
collect_email

hdr "יוצר קבצים"
gen_workflow   && ok ".github/workflows/supabase-keep-alive.yml עודכן"
gen_checklist  && ok "secrets-checklist.txt נוצר"
update_gitignore

set_secrets
print_next_steps
echo -e "${GREEN}${BOLD}✅ הגדרה הושלמה!${NC}\n"
