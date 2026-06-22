# Supabase Keep-Alive-Template

אוטומציה שמונעת השהיה של פרויקטי Supabase בחינם.

> Supabase משהה פרויקטים בחינם לאחר **7 ימים ללא פעילות**.
> הוורקפלו הזה מריץ query אמיתי ל-DB בכל פרויקט פעמיים בשבוע — בניגוד ל-health ping שאינו מאפס את טיימר הפעילות.

---

## מה קורה בכל ריצה

- DB query אמיתי (`/rest/v1/keep_alive`) על כל פרויקט → מצפה ל-HTTP 200
- דוח במייל עם סטטוס כל פרויקט (הצלחה + כישלון)
- אם פרויקט לא ענה — הוורקפלו נכשל ומופיע ב-Actions

> **למה לא health ping?** `/auth/v1/health` לא מגיע ל-Postgres ולכן לא מאפס את טיימר הפעילות של Supabase. רק query אמיתי ל-DB עושה זאת.

**לוח זמנים:** כל יום שני + רביעי, 08:00 UTC (11:00 ישראל)

---

## דרישות מקדימות

- חשבון GitHub (חינמי)
- פרויקט Supabase אחד לפחות
- חשבון Gmail עם אימות דו-שלבי *(אופציונלי — לדוחות מייל)*
- VS Code — **מומלץ** (ראו הוראות בהמשך)

---

## הגדרה מהירה (אוטומטית)

לאחר Fork ופתיחת הרפו ב-VS Code, הריצו בטרמינל:

```bash
bash setup.sh
```

הסקריפט ישאל שאלות, יוצר את הוורקפלו המותאם אישית, ויגדיר את כל ה-secrets ב-GitHub אוטומטית.

**דרישה:** [gh CLI](https://cli.github.com) — הסקריפט יציע להתקין אם לא קיים.

### הגדרה עם Claude Code

אם משתמשים ב-[Claude Code](https://claude.ai/code), צרו קובץ `~/.claude/commands/supabase-keep-alive-setup.md` עם התוכן הבא:

```
Guide the user through setting up the Supabase Keep-Alive template step by step.

The template repository is at: https://github.com/eyaldr/supabase-keep-alive-template

## Setup flow

1. **Check if the user already has a fork/clone**
   - Ask: "האם כבר עשיתם Fork לרפו וקלנתם אותו מקומית?"
   - If not: instruct them to go to https://github.com/eyaldr/supabase-keep-alive-template, click Fork, then clone it locally.

2. **Navigate to the cloned directory**
   - Ask for the path or detect it
   - `cd` into it and verify `setup.sh` exists

3. **Run setup.sh**
   - Run `bash setup.sh` in the cloned directory
   - Guide the user through each prompt:
     - Number of projects (1–4)
     - Per project: name, Supabase URL, anon key
     - Email reports (optional)
   - If gh CLI is not installed, help with installation

4. **SQL setup in Supabase**
   - After setup.sh completes, remind the user to run the SQL in each Supabase project's SQL Editor
   - The SQL is printed by setup.sh — just confirm they ran it

5. **Verify**
   - Instruct: GitHub → Actions → Supabase Keep-Alive → Run workflow → Run workflow
   - Wait ~30 seconds and confirm the run succeeded

Throughout the process: answer questions, help debug errors, and explain what each step does.
```

ואז הקלידו `/supabase-keep-alive-setup` — Claude ינחה אתכם שלב אחרי שלב.

---

## הגדרה ידנית שלב אחרי שלב

### שלב 1 — Fork את הרפו

לחצו **Fork** בפינה הימנית העליונה של דף GitHub.

בחרו שם (למשל `supabase-keep-alive`) → **Create fork**.

---

### שלב 2 — פתחו ב-VS Code

**אפשרות א׳ — מהדפדפן:**
בדף ה-Fork שלכם, לחצו על מקש `.` (נקודה) — VS Code נפתח ישירות בדפדפן.

**אפשרות ב׳ — מקומי:**
```bash
git clone https://github.com/<your-username>/supabase-keep-alive.git
cd supabase-keep-alive
code .
```

**התקנת Extensions (מומלץ):**
בפתיחה ב-VS Code תופיע הודעה:
> "This repository recommends extensions. Do you want to install them?"

לחצו **Install** — יותקנו:
- **GitHub Actions** — syntax highlighting, autocomplete, ואפשרות לצפות בריצות מ-VS Code
- **YAML** — אימות syntax בזמן אמת

אם ההודעה לא מופיעה: `Ctrl+Shift+P` → `Show Recommended Extensions`.

---

### שלב 3 — הכינו את ה-DB בכל פרויקט Supabase (חד-פעמי)

פתחו **Supabase Dashboard → SQL Editor** והריצו את ה-SQL הזה בכל אחד מהפרויקטים:

```sql
-- יצירת הטבלה
create table if not exists keep_alive (
  id serial primary key,
  last_ping timestamptz default now()
);

insert into keep_alive default values;

-- הפעלת RLS + מדיניות קריאה בלבד (מונע התראת אבטחה של Supabase)
alter table keep_alive enable row level security;
create policy "allow_anon_select" on keep_alive for select to anon using (true);
```

**הודעת Supabase בהרצה:** תופיע ההודעה _"Potential issue detected — Row Level Security"_ — לחצו **"Run and enable RLS"**.

**בטיחות:** RLS מופעל עם מדיניות SELECT בלבד — גורמים חיצוניים לא יכולים לכתוב או למחוק. אין מגע בטבלאות קיימות ואין השפעה על משתמשים אחרים.

---

### שלב 4 — התאימו את הוורקפלו לפרויקטים שלכם (שנו placeholders)

פתחו `.github/workflows/supabase-keep-alive.yml`.

**א׳ — שנו שמות פרויקטים:**
בכל step, עדכנו את שם ה-step ואת שמות ה-secrets:

```yaml
# לפני:
- name: Ping Project-1
  run: |
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
      "${{ secrets.PROJECT_1_URL }}/rest/v1/keep_alive?select=id&limit=1" \
      -H "apikey: ${{ secrets.PROJECT_1_K }}" \
      -H "Authorization: Bearer ${{ secrets.PROJECT_1_K }}")

# אחרי (לדוגמה):
- name: Ping My-App
  run: |
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
      "${{ secrets.MY_APP_URL }}/rest/v1/keep_alive?select=id&limit=1" \
      -H "apikey: ${{ secrets.MY_APP_K }}" \
      -H "Authorization: Bearer ${{ secrets.MY_APP_K }}")
```

**ב׳ — כמה פרויקטים יש לכם?**

| מצב | מה לעשות |
|-----|---------|
| פחות מ-4 | מחקו את ה-steps של Project-3 / Project-4 (כולל השורות שלהם ב-summary, email, ו-fail check) |
| יותר מ-4 | העתיקו step קיים, הוסיפו `id: p5` וכו׳, ועדכנו את שלבי ה-summary |

---

### שלב 5 — הגדירו GitHub Secrets

עברו לדף ה-Fork שלכם ב-GitHub:
**Settings → Secrets and variables → Actions → New repository secret**

> **חשוב:** שמות ה-secrets חייבים להתאים בדיוק לשמות שבחרתם בשלב 4. אם שיניתם `PROJECT_1` ל-`MY_APP` — הכניסו `MY_APP_URL` ו-`MY_APP_K` כאן.

**Secrets לכל פרויקט Supabase:**

| Secret | הכרחי? | איפה מוצאים |
|--------|:------:|------------|
| `PROJECT_1_URL` | ✅ | Supabase Dashboard → Project Settings → API → **Project URL** |
| `PROJECT_1_K` | ✅ | Supabase Dashboard → Project Settings → API → **Project API keys → anon / public** |
| `PROJECT_2_URL` | ✅ | כנ"ל לפרויקט 2 |
| `PROJECT_2_K` | ✅ | כנ"ל לפרויקט 2 |
| `PROJECT_3_URL` | רשות | רק אם שמרתם את שלב Project-3 בוורקפלו |
| `PROJECT_3_K` | רשות | כנ"ל |
| `PROJECT_4_URL` | רשות | רק אם שמרתם את שלב Project-4 בוורקפלו |
| `PROJECT_4_K` | רשות | כנ"ל |

**Secrets לדוחות מייל** *(רק אם שמרתם את שלב `Send email report`)*:

| Secret | ערך |
|--------|-----|
| `GMAIL_USERNAME` | כתובת Gmail שתשלח ותקבל את הדוחות |
| `GMAIL_APP_PASSWORD` | סיסמת App Password (ראו הוראות למטה) |

**יצירת Gmail App Password:**
1. Google Account → **Security**
2. הפעילו **2-Step Verification** (אם לא פעיל)
3. חזרו ל-Security → **App passwords**
4. בחרו `Other` → הזינו שם כלשהו → **Generate**
5. קבלו סיסמת 16 תווים — העתיקו ישירות ל-GitHub Secret

**ראו גם:** `secrets.template.txt` — רשימה מלאה של כל ה-secrets למילוי.

---

### שלב 6 — בדיקת ריצה ידנית

ב-GitHub → **Actions → Supabase Keep-Alive → Run workflow → Run workflow**

אחרי ~30 שניות:
- ✅ הריצה הצליחה — בדקו שהמייל הגיע
- ❌ הריצה נכשלה — לחצו על הריצה ובדקו איזה step נכשל

---

### שלב 7 — אימות שה-query הגיע ל-Supabase

Supabase Dashboard → בחרו פרויקט → **Logs → API**

חפשו בקשה ל-`/rest/v1/keep_alive` בזמן הריצה.

---

## שינוי לוח הזמנים

בוורקפלו, שורה cron:

```yaml
- cron: "0 8 * * 1,3"   # ב' + ד' ב-08:00 UTC
```

| cron | תדירות |
|------|--------|
| `0 8 * * 1` | פעם בשבוע — יום שני |
| `0 8 * * 1,3,5` | שלוש פעמים — ב', ד', ו' |
| `0 6 * * 1,3` | ב' + ד' ב-09:00 ישראל |

כלי עזר לבניית cron expressions: [crontab.guru](https://crontab.guru)

---

## השבתת דוחות מייל

מחקו את ה-step בשם `Send email report` מהוורקפלו (כולל שורות `uses:`, `with:` וכל השדות שתחתיו).

---

## מבנה הרפו

```
.github/
  workflows/
    supabase-keep-alive.yml   # הוורקפלו הראשי — כאן עורכים
.vscode/
  extensions.json             # המלצות extensions ל-VS Code
  settings.json               # schema אוטומטי ל-YAML
setup.sh                      # סקריפט הגדרה אוטומטי
secrets.template.txt          # רשימת secrets למילוי
README.md                     # המסמך הזה
```

---

## שאלות נפוצות

**הוורקפלו לא מוצג ב-Actions**
ב-GitHub → Actions → לחצו "I understand my workflows, go ahead and enable them"

**המייל לא מגיע**
בדקו שה-App Password הוכנס ללא רווחים, ושה-GMAIL_USERNAME נכון.

**Supabase עדיין מושהה**
בדקו שהפינג הגיע ב-Logs. אם הוא מגיע ועדיין קורה — פנו ל-Supabase Support.
