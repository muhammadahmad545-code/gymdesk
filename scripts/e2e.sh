# Sourced by smoke.sh. End-to-end checks of Gymdesk's main flows on the emulator.
# Some keyboards ignore ESC; fall back to Back while the keyboard is still showing.
hide_keyboard() {
  adb shell input keyevent 111; sleep 1
  if adb shell dumpsys input_method | grep -qE "mInputShown=true|isInputShown=true"; then adb shell input keyevent 4; sleep 1; fi
}
# Starts on Home after a relaunch.

# The emulator screen is small; scroll with coordinates relative to its real size.
read -r W H <<<"$(adb shell wm size | grep -o '[0-9]*x[0-9]*' | tail -1 | tr x ' ')"
W=${W:-1080}; H=${H:-1920}
swipe_up() { adb shell input swipe $((W/2)) $((H*70/100)) $((W/2)) $((H*35/100)) 400; sleep 1; }
scroll_to() {
  for i in $(seq 1 10); do has_text "$1" && return 0; swipe_up; done
  has_text "$1"
}
# Scroll until an exact label sits in the upper part of the screen (clear of the tab bar), then tap it.
scroll_tap() {
  for i in $(seq 1 10); do
    dump; xy=$(_find exact "$1")
    if [ -n "$xy" ] && [ "${xy#* }" -lt $((H*65/100)) ]; then adb shell input tap $xy; echo "tapped '$1' at $xy"; return 0; fi
    swipe_up
  done
  return 1
}

clear_field() { for i in $(seq 1 14); do adb shell input keyevent 67; done; }
pin() { for d in $(echo "$1" | grep -o .); do tap_text "$d" >/dev/null; done; }

wait_for "Mark attendance" 20
expect "Check-ins 0" 10 "dashboard starts with no check-ins"

# --- Add a member who has not paid yet -------------------------------------------------
tap_text "Members"; sleep 2
tap_text "Add member"; sleep 3
expect "Save member" 10 "add-member form opens"
tap_class EditText 0; type_text "Test Member"
tap_class EditText 1; type_text "03001234567"
hide_keyboard
scroll_to "First fee paid" >/dev/null
tap_contains "First fee paid"; sleep 1
expect "The fee will show as due" 5 "first-fee switch turns off"
tap_text "Save member"; sleep 3
expect "Test Member" 10 "new member is listed"
shot e2e-1-members
alive || fail "app died after adding a member"

# --- Dashboard sees the unpaid member ------------------------------------------------------
tap_text "Home"; sleep 3
expect "Due soon 1" 10 "dashboard counts the member as due"
expect "Revenue Rs 0" 5 "no revenue before a payment"
shot e2e-2-home-due

# --- Search ---------------------------------------------------------------------------------
tap_text "Members"; sleep 2
tap_class EditText 0; type_text "Test Mem"; hide_keyboard
expect "Test Member" 5 "search finds the member"
tap_class EditText 0; type_text "zzz"; hide_keyboard
expect_not "Test Member" 1 "search with no match hides the member"
tap_class EditText 0; clear_field; type_text "0300123"; hide_keyboard
expect "Test Member" 5 "search by phone number finds the member"

# --- Member detail: attendance and payment ---------------------------------------------------
tap_text "Test Member"; sleep 3
expect "No payments recorded yet" 10 "member detail opens with no payments"
tap_text "Check in"; sleep 3
expect "Checked in today" 8 "attendance is marked"
tap_first "Record payment"; sleep 2
expect "Save payment" 8 "payment sheet opens"
shot e2e-3-payment-sheet
tap_text "Save payment"; sleep 3
expect "Payment saved" 5 "payment is saved"
expect_not "No payments recorded yet" 1 "payment shows in the log"
shot e2e-4-detail
back; sleep 1
hide_keyboard

# --- Dashboard counts update ----------------------------------------------------------------
tap_text "Home"; sleep 3
expect "Check-ins 1" 10 "dashboard counts the check-in"
expect "Due soon 0" 5 "paid member no longer counts as due"
expect "Revenue Rs 3,000" 5 "revenue includes the payment"
shot e2e-5-home-paid

# --- Mark attendance from the front-desk screen ------------------------------------------------
tap_text "Mark attendance"; sleep 3
expect "1 checked in today" 8 "attendance screen shows today's count"
tap_contains "Test Member"; sleep 2
expect "already checked in today" 5 "a second check-in on the same day is refused"
back; sleep 1; back; sleep 1

# --- Everything persists after a relaunch --------------------------------------------------------
adb shell am force-stop "$PKG"; sleep 2
launch
wait_for "Mark attendance" 20
expect "Check-ins 1" 10 "check-in persists after relaunch"
expect "Revenue Rs 3,000" 5 "payment persists after relaunch"
tap_text "Members"; sleep 2
expect "Test Member" 10 "member persists after relaunch"
tap_text "Test Member"; sleep 3
expect "Checked in today" 8 "attendance persists on the member"
expect_not "No payments recorded yet" 1 "payment log persists"
back; sleep 1

# --- Analytics shows the payment --------------------------------------------------------------
tap_text "Analytics"; sleep 3
expect "Collected Rs 3,000" 8 "analytics counts this month's revenue"
shot e2e-6-analytics

# --- Expenses and profit ----------------------------------------------------------------------
expect "Profit this month" 5 "analytics shows profit"
tap_text "Profit this month. Open expenses" || tap_contains "Profit this month"; sleep 3
expect "No expenses this month" 8 "expenses screen opens"
tap_text "Add expense"; sleep 2
tap_class EditText 0; type_text "1000"
# Enter saves the form (a Back press here would close the sheet instead).
adb shell input keyevent 66; sleep 3
expect "Rs 2,000" 8 "profit is fees minus expenses"
expect "Rent" 5 "expense listed with its category"
shot e2e-6b-expenses
back; sleep 2
expect "Rs 2,000" 8 "analytics profit includes the expense"

# --- Quick access: launcher shortcuts and the widget ------------------------------------------
adb shell dumpsys shortcut > "$OUT/shortcuts.txt" 2>/dev/null
grep -A40 "Package: $PKG" "$OUT/shortcuts.txt" | grep -q "id=checkin" && pass "launcher shortcuts installed" || fail "launcher shortcuts installed"
adb shell dumpsys appwidget > "$OUT/appwidget.txt" 2>/dev/null
grep -q "$PKG/$PKG.GymWidget" "$OUT/appwidget.txt" && pass "home-screen widget is offered" || fail "home-screen widget is offered"
adb shell am start -n "$PKG/.MainActivity" --es gymdesk.action checkin >/dev/null 2>&1; sleep 4
shot e2e-6c-shortcut
# The search field has focus and the keyboard is up, so check without scrolling (a swipe would type).
if has_text "checked in today"; then pass "Mark attendance shortcut opens check-in"; else fail "Mark attendance shortcut opens check-in"; fi
adb shell am force-stop "$PKG"; sleep 2
launch
wait_for "Mark attendance" 20

# --- Optional PIN lock ------------------------------------------------------------------------
tap_text "Settings"; sleep 2
scroll_tap "App lock"; sleep 2
expect "Choose a PIN" 8 "PIN setup opens from Settings"
pin 1234; tap_text "Next"; sleep 2
expect "Confirm your PIN" 8 "PIN confirm step"
pin 1234; tap_text "Save PIN"; sleep 4
expect "A PIN is needed" 8 "app lock is on"
adb shell am force-stop "$PKG"; sleep 2
launch
expect "Enter PIN" 20 "lock screen appears after relaunch"
shot e2e-7-lock
pin 9999; tap_text "Unlock"; sleep 3
expect "Wrong PIN" 5 "wrong PIN is rejected"
pin 1234; tap_text "Unlock"; sleep 4
expect "Mark attendance" 10 "correct PIN unlocks"
tap_text "Settings"; sleep 2
scroll_tap "App lock"; sleep 2
expect "Enter your current PIN" 8 "turning the lock off asks for the PIN"
pin 1234; tap_text "Continue"; sleep 3
adb shell am force-stop "$PKG"; sleep 2
launch
expect "Mark attendance" 20 "app opens without a PIN once the lock is off"
expect_not "Enter PIN" 1 "no lock screen after turning the lock off"
alive || fail "app died during the end-to-end tests"

# --- Appearance: draft preview, Apply, persistence after restart, reset -----------------------
is_selected() { dump; python3 - "$1" <<'PY'
import re, sys, html
xml = open('/tmp/ui.xml', encoding='utf-8', errors='ignore').read()
for m in re.finditer(r'<node [^>]*>', xml):
    n = m.group(0)
    vals = [html.unescape(v) for v in re.findall(r' (?:text|content-desc)="([^"]*)"', n)]
    if any(v == sys.argv[1] or sys.argv[1] in v.split('\n') for v in vals):
        sys.exit(0 if ('selected="true"' in n or 'checked="true"' in n) else 1)
sys.exit(1)
PY
}
tap_text "Settings"; sleep 2
scroll_tap "Appearance"; sleep 3
expect "Gymdesk, your way" 10 "Appearance screen opens with a live preview"
shot e2e-8-appearance
scroll_tap "Teal accent"; sleep 1
scroll_tap "Manrope font"; sleep 1
scroll_tap "Warm background"; sleep 1
scroll_tap "Glass"; sleep 1
scroll_tap "Floating"; sleep 1
shot e2e-8-appearance-draft
expect "Apply" 5 "changes wait for Apply"
tap_text "Apply"; sleep 2
expect_not "Discard" 2 "Apply saves the draft"
back
shot e2e-8-appearance-applied
adb shell am force-stop "$PKG"; sleep 2
launch
expect "Mark attendance" 20 "app reopens after changing the appearance"
shot e2e-8-appearance-after-restart
tap_text "Settings"; sleep 2
scroll_tap "Appearance"; sleep 3
for i in 1 2 3; do has_text "Teal accent" && break; swipe_up; done
if is_selected "Teal accent"; then pass "accent choice survives a restart"; else fail "accent choice survives a restart"; fi
scroll_to "Manrope font" >/dev/null
if is_selected "Manrope font"; then pass "font choice survives a restart"; else fail "font choice survives a restart"; fi
scroll_tap "Reset to default"; sleep 1
tap_text "Apply"; sleep 2
scroll_top
for i in 1 2 3; do has_text "Gymdesk accent" && break; swipe_up; done
if is_selected "Gymdesk accent"; then pass "Reset to default returns to the app colour"; else fail "Reset to default returns to the app colour"; fi
back
alive || fail "app died during the appearance checks"
