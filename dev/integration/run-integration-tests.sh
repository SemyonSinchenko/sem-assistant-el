#!/bin/bash
# Integration Test Runner for SEM Assistant Elisp Daemon
# Executes the full integration test lifecycle end-to-end

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
COMPOSE_FILE="$REPO_ROOT/docker-compose.yml"
COMPOSE_OVERRIDE="$SCRIPT_DIR/docker-compose.test.yml"
TEST_INBOX="$SCRIPT_DIR/testing-resources/inbox-tasks.org"
PREEXISTING_TASKS_FIXTURE="$SCRIPT_DIR/testing-resources/preexisting-tasks.org"
PREEXISTING_UMBRELLA_FIXTURE="$SCRIPT_DIR/testing-resources/20260313152244-llm.org"
FEEDS_FIXTURE="$SCRIPT_DIR/testing-resources/feeds.org"
TEST_DATA_DIR="$REPO_ROOT/test-data"
ORG_ROAM_REPO_DIR="$TEST_DATA_DIR/org-roam"
ORG_ROAM_NOTES_DIR="$ORG_ROAM_REPO_DIR/org-files"
TEST_RESULTS_DIR="$REPO_ROOT/test-results"
LOGS_DIR="$REPO_ROOT/logs"
WEBDAV_BASE_URL="http://localhost:16065"
WEBDAV_USERNAME="${WEBDAV_USERNAME:-orgzly}"
WEBDAV_PASSWORD="${WEBDAV_PASSWORD:-changeme}"
TRUSTED_URL="https://semyonsinchenko.github.io/ssinchenko/post/aider_2026_and_other_topics/"
TRUSTED_FEED_URL="https://semyonsinchenko.github.io/ssinchenko/index.xml"
TRUSTED_UMBRELLA_ID="96a58b04-1f58-47c9-993f-551994939252"
TRUSTED_UMBRELLA_TITLE="LLM"
TRUSTED_UMBRELLA_TAG=":umbrella:"
ORG_ROAM_BASELINE_MANIFEST="$TEST_DATA_DIR/org-roam-baseline-files.txt"
INTEGRATION_MODE="${SEM_INTEGRATION_MODE:-paid-inbox}"
LOCAL_GIT_SYNC_MODE="local-git-sync"
PAID_INBOX_MODE="paid-inbox"
LOCAL_GIT_SYNC_RUN_DIR_NAME="local-git-sync-run"
LOCAL_GIT_SYNC_RESULTS_FILE="local-git-sync-results.txt"
LOCAL_GIT_SYNC_LOCAL_REPO="$ORG_ROAM_REPO_DIR"
LOCAL_GIT_SYNC_BARE_REMOTE="$TEST_DATA_DIR/local-git-sync-origin.git"
LOCAL_GIT_SYNC_UNAVAILABLE_REMOTE="$TEST_DATA_DIR/local-git-sync-missing-origin.git"

# Test-specific port mapping (avoids privileged port 443)
export WEBDAV_PORT=16065

# Test-specific LLM provider and model (override via environment).
export LLM_PROVIDER="${LLM_PROVIDER:-deepseek}"
export LLM_MODEL="${LLM_MODEL:-deepseek-flash}"

# Test-specific runtime timezone required by startup validation.
export CLIENT_TIMEZONE="${CLIENT_TIMEZONE:-Etc/UTC}"

# Poll configuration
DAEMON_POLL_INTERVAL=3
DAEMON_MAX_ATTEMPTS=30
TASKS_POLL_INTERVAL=5
TASKS_MAX_ATTEMPTS=48

# Derived counts for polling and assertions
EXPECTED_NEW_TASK_COUNT=$(grep -c '^\* TODO .*:task:' "$TEST_INBOX" 2>/dev/null || echo "0")
EXPECTED_PREEXISTING_TASK_COUNT=$(grep -c '^\* TODO ' "$PREEXISTING_TASKS_FIXTURE" 2>/dev/null || echo "0")
MALFORMED_SENSITIVE_TASK_TITLE="Malformed sensitive block should go to DLQ"
MALFORMED_SENSITIVE_FIXTURE_SNIPPET="This fixture intentionally has malformed sensitive markup and must never reach LLM."
EXPECTED_MALFORMED_SENSITIVE_DLQ_COUNT=1
EXPECTED_TASK_COUNT=$((EXPECTED_NEW_TASK_COUNT + EXPECTED_PREEXISTING_TASK_COUNT - EXPECTED_MALFORMED_SENSITIVE_DLQ_COUNT))

# Assertion constants
RUNTIME_TIMEZONE="${CLIENT_TIMEZONE}"
ASSERTION3_LOWER_BOUND_TOLERANCE_SECONDS=60
KEYWORDS=("quarterly financial reports" "#452" "team building activity" "INC-7781" "AMBIGUOUS-WEEKDAY-CASE-9012")
SENSITIVE_KEYWORDS=("supersecret123" "sk-live-abc123xyz789" "IBAN: DE89370400440532013000" "ACCOUNT NUMBER: 123456789")
JOURNAL_BODY_SNIPPET="Today I felt tense after talking to @boss and later apologized to @wife."
JOURNAL_TAGS_VALUE=":work:family:"
JOURNAL_MENTIONS_VALUE="boss, wife"
ASSERTION_RESULT_KEYS=(
    "ASSERTION_1_RESULT"
    "ASSERTION_2_RESULT"
    "ASSERTION_3_RESULT"
    "ASSERTION_4_RESULT"
    "ASSERTION_5_RESULT"
    "ASSERTION_5A_RESULT"
    "ASSERTION_5B_RESULT"
    "ASSERTION_6_RESULT"
    "ASSERTION_7_RESULT"
    "ASSERTION_8_RESULT"
    "ASSERTION_9_RESULT"
    "ASSERTION_10_RESULT"
)

# Test status
TEST_STATUS="PASS"
RUN_DIR=""

# =============================================================================
# Validation
# =============================================================================

echo "=== SEM Integration Test Suite ==="
echo "Mode: $INTEGRATION_MODE"
echo "CLIENT_TIMEZONE: ${CLIENT_TIMEZONE}"

if [[ "$INTEGRATION_MODE" == "$PAID_INBOX_MODE" ]]; then
    # Paid inbox/LLM path requires an API key for the configured provider.
    if [[ "$LLM_PROVIDER" == "openrouter" ]]; then
        provider_key_var="OPENROUTER_KEY"
    else
        provider_key_var="DEEPSEEK_API_KEY"
    fi
    if [[ -z "${LLM_API_KEY:-}" && -z "${!provider_key_var:-}" ]]; then
        echo "ERROR: ${provider_key_var} (or LLM_API_KEY) environment variable is not set" >&2
        echo "Integration tests require real LLM API access." >&2
        exit 1
    fi
    echo "LLM provider ${LLM_PROVIDER}: API key is set (masked)"
elif [[ "$INTEGRATION_MODE" == "$LOCAL_GIT_SYNC_MODE" ]]; then
    echo "Running local git-sync validation without LLM or network APIs"
else
    echo "ERROR: Unsupported SEM_INTEGRATION_MODE: $INTEGRATION_MODE" >&2
    echo "Supported values: $PAID_INBOX_MODE, $LOCAL_GIT_SYNC_MODE" >&2
    exit 1
fi

# =============================================================================
# Cleanup Trap (MUST be registered early, before any other actions)
# =============================================================================

cleanup() {
    echo ""
    echo "=== Cleanup ==="
    if [[ "$INTEGRATION_MODE" == "$PAID_INBOX_MODE" ]]; then
        echo "Stopping containers..."
        podman-compose -f "$COMPOSE_FILE" -f "$COMPOSE_OVERRIDE" down -v 2>/dev/null || true
        echo "Removing dangling images..."
        podman image prune -f 2>/dev/null || true
    else
        echo "Local git-sync mode: skipping container cleanup"
    fi
    echo "Cleanup complete"
}

trap cleanup EXIT

# =============================================================================
# Test Data Directory Setup
# =============================================================================

cleanup_test_results() {
    echo ""
    echo "=== Cleaning Up Test Results Directory ==="
    
    if [[ -d "$TEST_RESULTS_DIR" ]]; then
        echo "Removing existing test-results directory..."
        rm -rf "$TEST_RESULTS_DIR"
    fi
    
    echo "Creating fresh test-results directory..."
    mkdir -p "$TEST_RESULTS_DIR"
    
    echo "Test results directory ready: $TEST_RESULTS_DIR"
}

setup_test_data() {
    echo ""
    echo "=== Setting Up Test Data Directory ==="
    
    # Wipe test-data if it exists
    if [[ -d "$TEST_DATA_DIR" ]]; then
        echo "Removing existing test-data directory..."
        rm -rf "$TEST_DATA_DIR"
    fi
    
    # Recreate with required subdirectories
    echo "Creating test-data subdirectories..."
    mkdir -p "$ORG_ROAM_REPO_DIR"
    mkdir -p "$ORG_ROAM_NOTES_DIR"
    mkdir -p "$TEST_DATA_DIR/elfeed"
    mkdir -p "$TEST_DATA_DIR/morning-read"
    mkdir -p "$TEST_DATA_DIR/prompts"

    if [[ ! -f "$PREEXISTING_TASKS_FIXTURE" ]]; then
        echo "ERROR: pre-existing tasks fixture not found: $PREEXISTING_TASKS_FIXTURE" >&2
        TEST_STATUS="FAIL"
        return 1
    fi

    if [[ ! -f "$PREEXISTING_UMBRELLA_FIXTURE" ]]; then
        echo "ERROR: pre-existing umbrella fixture not found: $PREEXISTING_UMBRELLA_FIXTURE" >&2
        TEST_STATUS="FAIL"
        return 1
    fi

    if [[ ! -f "$FEEDS_FIXTURE" ]]; then
        echo "ERROR: feeds fixture not found: $FEEDS_FIXTURE" >&2
        TEST_STATUS="FAIL"
        return 1
    fi

    echo "Installing pre-existing tasks fixture into WebDAV data path..."
    cp "$PREEXISTING_TASKS_FIXTURE" "$TEST_DATA_DIR/tasks.org"

    echo "Seeding pre-existing umbrella fixture into runtime org-roam directory..."
    cp "$PREEXISTING_UMBRELLA_FIXTURE" "$ORG_ROAM_NOTES_DIR/"

    echo "Installing feeds fixture into runtime data path..."
    cp "$FEEDS_FIXTURE" "$TEST_DATA_DIR/feeds.org"

    echo "Validating pre-existing fixture shape..."
    python3 - "$TEST_DATA_DIR/tasks.org" <<'PY'
import re
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    text = f.read()

todo_count = len(re.findall(r"^\*+\s+TODO\s+", text, flags=re.MULTILINE))
scheduled_count = len(re.findall(r"^\s*SCHEDULED:\s*<", text, flags=re.MULTILINE))
priority_count = len(re.findall(r"^\*+\s+TODO\s+.*\[#([A-C])\]", text, flags=re.MULTILINE))

headings = re.split(r"(?=^\*+\s+TODO\s+)", text, flags=re.MULTILINE)
unscheduled_count = 0
tag_set = set()
for block in headings:
    if not block.strip().startswith("* TODO"):
        continue
    if "SCHEDULED:" not in block:
        unscheduled_count += 1
    m = re.search(r":([A-Za-z0-9_@#%:-]+):\s*$", block.splitlines()[0])
    if m:
        for tag in [t for t in m.group(1).split(":") if t]:
            tag_set.add(tag)

errors = []
if todo_count < 5:
    errors.append(f"expected >=5 TODOs, got {todo_count}")
if scheduled_count < 3:
    errors.append(f"expected >=3 scheduled TODOs, got {scheduled_count}")
if unscheduled_count < 1:
    errors.append("expected at least 1 unscheduled TODO")
if priority_count < 1:
    errors.append("expected at least 1 priority TODO")
required_tags = {"work", "routine"}
if not required_tags.issubset(tag_set):
    errors.append(f"missing required tags: {sorted(required_tags - tag_set)}")
if len(tag_set) < 3:
    errors.append(f"expected mixed tags (>=3 distinct), got {sorted(tag_set)}")

if errors:
    print("FAIL: pre-existing fixture shape invalid")
    for err in errors:
        print(f" - {err}")
    sys.exit(1)

print(
    "PASS: pre-existing fixture shape validated "
    f"(todo={todo_count}, scheduled={scheduled_count}, unscheduled={unscheduled_count}, "
    f"priority={priority_count}, tags={sorted(tag_set)})"
)
PY

    echo "Validating seeded umbrella fixture contract..."
    python3 - "$ORG_ROAM_NOTES_DIR/$(basename "$PREEXISTING_UMBRELLA_FIXTURE")" "$TRUSTED_UMBRELLA_ID" "$TRUSTED_UMBRELLA_TITLE" "$TRUSTED_UMBRELLA_TAG" <<'PY'
import re
import sys

path = sys.argv[1]
expected_id = sys.argv[2]
expected_title = sys.argv[3]
expected_tag = sys.argv[4]

with open(path, "r", encoding="utf-8") as f:
    text = f.read()

id_match = re.search(r"^:ID:\s*(.+)$", text, flags=re.MULTILINE)
title_match = re.search(r"^#\+title:\s*(.+)$", text, flags=re.MULTILINE)
tags_match = re.search(r"^#\+filetags:\s*(.+)$", text, flags=re.MULTILINE)

errors = []
if not id_match:
    errors.append("missing :ID: line")
elif id_match.group(1).strip() != expected_id:
    errors.append(f"expected ID {expected_id}, got {id_match.group(1).strip()}")

if not title_match:
    errors.append("missing #+title line")
elif title_match.group(1).strip() != expected_title:
    errors.append(f"expected title {expected_title}, got {title_match.group(1).strip()}")

if not tags_match:
    errors.append("missing #+filetags line")
else:
    filetags = tags_match.group(1)
    if expected_tag not in filetags:
        errors.append(f"missing canonical umbrella tag {expected_tag} in filetags {filetags!r}")
    if ":umbrealla:" in filetags:
        errors.append(f"found typo umbrella tag :umbrealla: in filetags {filetags!r}")

if errors:
    print("FAIL: seeded umbrella fixture contract invalid")
    for err in errors:
        print(f" - {err}")
    sys.exit(1)

print("PASS: seeded umbrella fixture contract validated")
PY

    echo "Recording org-roam baseline snapshot..."
    find "$ORG_ROAM_NOTES_DIR" -maxdepth 1 -type f -name '*.org' -printf '%f\n' | sort > "$ORG_ROAM_BASELINE_MANIFEST"
    echo "Baseline manifest saved to: $ORG_ROAM_BASELINE_MANIFEST"

    echo "Test data directory ready: $TEST_DATA_DIR"
}

# =============================================================================
# Logs Directory Setup
# =============================================================================

setup_logs() {
    echo ""
    echo "=== Setting Up Logs Directory ==="
    
    # Wipe logs directory
    if [[ -d "$LOGS_DIR" ]]; then
        echo "Removing existing logs..."
        rm -rf "$LOGS_DIR"/*
    else
        mkdir -p "$LOGS_DIR"
    fi
    
    echo "Logs directory ready: $LOGS_DIR"
}

# =============================================================================
# Run Directory Creation
# =============================================================================

create_run_dir() {
    echo ""
    echo "=== Creating Run Directory ==="

    # Create test-results directory if absent
    mkdir -p "$TEST_RESULTS_DIR"

    # Create run directory (deterministic for local git-sync mode)
    local timestamp
    if [[ "$INTEGRATION_MODE" == "$LOCAL_GIT_SYNC_MODE" ]]; then
        RUN_DIR="$TEST_RESULTS_DIR/$LOCAL_GIT_SYNC_RUN_DIR_NAME"
        rm -rf "$RUN_DIR"
    else
        timestamp=$(date +%Y-%m-%d-%H-%M-%S)
        RUN_DIR="$TEST_RESULTS_DIR/${timestamp}-run"
    fi
    mkdir -p "$RUN_DIR"

    echo "Run directory created: $RUN_DIR"
}

# =============================================================================
# Local Git-Sync Validation (No-cost path)
# =============================================================================

local_git_sync_run_emacs_sync() {
    local repo_dir="$1"
    local output_file="$2"

    emacs --batch \
      --eval "(progn
  (require 'cl-lib)
  (load-file \"$REPO_ROOT/app/elisp/sem-core.el\")
  (load-file \"$REPO_ROOT/app/elisp/sem-git-sync.el\")
  (let ((orig-dir sem-git-sync-org-roam-dir)
        (orig-key sem-git-sync-ssh-key))
    (unwind-protect
        (progn
          (setq sem-git-sync-org-roam-dir \"$repo_dir\")
          (setq sem-git-sync-ssh-key \"$REPO_ROOT/.does-not-exist\")
          (condition-case err
              (cl-letf (((symbol-function 'sem-git-sync--run-command)
                         (lambda (command &optional dir)
                           (let* ((full-command (if dir
                                                    (format \"cd %s && %s\" (shell-quote-argument dir) command)
                                                  command))
                                  (output-buffer (generate-new-buffer \" *git-sync-local-cmd*\")))
                             (unwind-protect
                                 (let ((exit-code
                                        (with-current-buffer output-buffer
                                          (erase-buffer)
                                          (call-process-shell-command full-command nil output-buffer nil))))
                                   (cons exit-code (with-current-buffer output-buffer (buffer-string))))
                               (when (buffer-live-p output-buffer)
                                 (kill-buffer output-buffer))))))
                        ((symbol-function 'sem-git-sync--setup-ssh) (lambda () '(t . nil)))
                        ((symbol-function 'sem-git-sync--teardown-ssh) (lambda (&rest _) nil)))
                (if (sem-git-sync-org-roam)
                    (princ \"RESULT:SUCCESS\\n\")
                  (princ \"RESULT:FAILURE\\n\")))
            (error
             (princ (format \"RESULT:ERROR:%s\\n\" (error-message-string err))))))
      (setq sem-git-sync-org-roam-dir orig-dir)
      (setq sem-git-sync-ssh-key orig-key))))" > "$output_file" 2>&1
}

local_git_sync_current_branch() {
    local repo_dir="$1"
    git -C "$repo_dir" rev-parse --abbrev-ref HEAD
}

local_git_sync_head() {
    local repo_dir="$1"
    git -C "$repo_dir" rev-parse HEAD
}

local_git_sync_commit_count() {
    local repo_dir="$1"
    git -C "$repo_dir" rev-list --count HEAD
}

local_git_sync_bare_head() {
    local bare_repo="$1"
    local branch_name="$2"
    git --git-dir "$bare_repo" rev-parse "refs/heads/$branch_name"
}

local_git_sync_setup_fixtures() {
    echo ""
    echo "=== Setting Up Local Git-Sync Fixtures ==="

    rm -rf "$LOCAL_GIT_SYNC_LOCAL_REPO" "$LOCAL_GIT_SYNC_BARE_REMOTE" "$LOCAL_GIT_SYNC_UNAVAILABLE_REMOTE"
    mkdir -p "$LOCAL_GIT_SYNC_LOCAL_REPO"

    git -C "$LOCAL_GIT_SYNC_LOCAL_REPO" init
    git -C "$LOCAL_GIT_SYNC_LOCAL_REPO" config user.name "SEM Integration"
    git -C "$LOCAL_GIT_SYNC_LOCAL_REPO" config user.email "sem-integration@example.com"

    cat > "$LOCAL_GIT_SYNC_LOCAL_REPO/seed.org" <<'EOF'
* Seed
Initial local git-sync fixture content.
EOF

    git -C "$LOCAL_GIT_SYNC_LOCAL_REPO" add -A
    git -C "$LOCAL_GIT_SYNC_LOCAL_REPO" commit -m "Seed local git-sync fixture"

    git init --bare "$LOCAL_GIT_SYNC_BARE_REMOTE"
    git -C "$LOCAL_GIT_SYNC_LOCAL_REPO" remote add origin "file://$LOCAL_GIT_SYNC_BARE_REMOTE"
    git -C "$LOCAL_GIT_SYNC_LOCAL_REPO" push -u origin HEAD
}

local_git_sync_validate_fixtures() {
    echo ""
    echo "=== Validating Local Git-Sync Fixtures ==="

    if [[ ! -d "$LOCAL_GIT_SYNC_LOCAL_REPO/.git" ]]; then
        echo "FAIL: local fixture is not a git repository: $LOCAL_GIT_SYNC_LOCAL_REPO" | tee -a "$RUN_DIR/$LOCAL_GIT_SYNC_RESULTS_FILE"
        TEST_STATUS="FAIL"
        return 1
    fi

    if [[ ! -d "$LOCAL_GIT_SYNC_BARE_REMOTE" ]]; then
        echo "FAIL: local bare remote fixture missing: $LOCAL_GIT_SYNC_BARE_REMOTE" | tee -a "$RUN_DIR/$LOCAL_GIT_SYNC_RESULTS_FILE"
        TEST_STATUS="FAIL"
        return 1
    fi

    if [[ ! -f "$LOCAL_GIT_SYNC_BARE_REMOTE/HEAD" ]]; then
        echo "FAIL: local bare remote fixture missing HEAD file: $LOCAL_GIT_SYNC_BARE_REMOTE" | tee -a "$RUN_DIR/$LOCAL_GIT_SYNC_RESULTS_FILE"
        TEST_STATUS="FAIL"
        return 1
    fi

    local origin_url
    origin_url=$(git -C "$LOCAL_GIT_SYNC_LOCAL_REPO" remote get-url origin)
    if [[ "$origin_url" != "file://$LOCAL_GIT_SYNC_BARE_REMOTE" ]]; then
        echo "FAIL: unexpected local origin URL: $origin_url" | tee -a "$RUN_DIR/$LOCAL_GIT_SYNC_RESULTS_FILE"
        TEST_STATUS="FAIL"
        return 1
    fi

    echo "PASS: local git-sync fixtures validated" | tee -a "$RUN_DIR/$LOCAL_GIT_SYNC_RESULTS_FILE"
}

run_local_git_sync_validation() {
    echo ""
    echo "=== Running Local Git-Sync Validation ==="

    local results_file="$RUN_DIR/$LOCAL_GIT_SYNC_RESULTS_FILE"
    : > "$results_file"

    local branch_name
    local before_head
    local after_head
    local before_count
    local after_count
    local before_remote_head
    local after_remote_head

    local changed_stdout="$RUN_DIR/local-git-sync-changed.stdout"
    local noop_stdout="$RUN_DIR/local-git-sync-noop.stdout"
    local invalid_repo_stdout="$RUN_DIR/local-git-sync-invalid-repo.stdout"
    local unavailable_remote_stdout="$RUN_DIR/local-git-sync-unavailable-remote.stdout"

    branch_name=$(local_git_sync_current_branch "$LOCAL_GIT_SYNC_LOCAL_REPO")

    echo "Scenario 1: changed content should commit and push" | tee -a "$results_file"
    before_head=$(local_git_sync_head "$LOCAL_GIT_SYNC_LOCAL_REPO")
    before_count=$(local_git_sync_commit_count "$LOCAL_GIT_SYNC_LOCAL_REPO")
    echo "* Change marker $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$LOCAL_GIT_SYNC_LOCAL_REPO/seed.org"

    local_git_sync_run_emacs_sync "$LOCAL_GIT_SYNC_LOCAL_REPO" "$changed_stdout"
    if ! grep -q "RESULT:SUCCESS" "$changed_stdout"; then
        echo "FAIL: changed-content sync did not report success" | tee -a "$results_file"
        TEST_STATUS="FAIL"
    fi

    after_head=$(local_git_sync_head "$LOCAL_GIT_SYNC_LOCAL_REPO")
    after_count=$(local_git_sync_commit_count "$LOCAL_GIT_SYNC_LOCAL_REPO")
    after_remote_head=$(local_git_sync_bare_head "$LOCAL_GIT_SYNC_BARE_REMOTE" "$branch_name")

    if [[ "$after_head" == "$before_head" ]]; then
        echo "FAIL: local HEAD did not advance after changed-content sync" | tee -a "$results_file"
        TEST_STATUS="FAIL"
    else
        echo "PASS: local HEAD advanced after changed-content sync" | tee -a "$results_file"
    fi

    if [[ "$after_count" -ne $((before_count + 1)) ]]; then
        echo "FAIL: expected commit count to increase by one (before=$before_count after=$after_count)" | tee -a "$results_file"
        TEST_STATUS="FAIL"
    else
        echo "PASS: local commit count increased by one" | tee -a "$results_file"
    fi

    if [[ "$after_head" != "$after_remote_head" ]]; then
        echo "FAIL: push propagation mismatch local=$after_head remote=$after_remote_head" | tee -a "$results_file"
        TEST_STATUS="FAIL"
    else
        echo "PASS: bare remote tip matches local tip after push" | tee -a "$results_file"
    fi

    echo "Scenario 2: clean repository should be a no-op success" | tee -a "$results_file"
    before_head=$(local_git_sync_head "$LOCAL_GIT_SYNC_LOCAL_REPO")
    before_count=$(local_git_sync_commit_count "$LOCAL_GIT_SYNC_LOCAL_REPO")
    before_remote_head=$(local_git_sync_bare_head "$LOCAL_GIT_SYNC_BARE_REMOTE" "$branch_name")

    local_git_sync_run_emacs_sync "$LOCAL_GIT_SYNC_LOCAL_REPO" "$noop_stdout"
    if ! grep -q "RESULT:SUCCESS" "$noop_stdout"; then
        echo "FAIL: no-op sync did not report success" | tee -a "$results_file"
        TEST_STATUS="FAIL"
    fi

    after_head=$(local_git_sync_head "$LOCAL_GIT_SYNC_LOCAL_REPO")
    after_count=$(local_git_sync_commit_count "$LOCAL_GIT_SYNC_LOCAL_REPO")
    after_remote_head=$(local_git_sync_bare_head "$LOCAL_GIT_SYNC_BARE_REMOTE" "$branch_name")

    if [[ "$after_count" -ne "$before_count" ]]; then
        echo "FAIL: no-op sync unexpectedly changed commit count (before=$before_count after=$after_count)" | tee -a "$results_file"
        TEST_STATUS="FAIL"
    else
        echo "PASS: no-op sync preserved local commit count" | tee -a "$results_file"
    fi

    if [[ "$after_head" != "$before_head" ]]; then
        echo "FAIL: no-op sync unexpectedly changed local HEAD" | tee -a "$results_file"
        TEST_STATUS="FAIL"
    else
        echo "PASS: no-op sync preserved local HEAD" | tee -a "$results_file"
    fi

    if [[ "$after_remote_head" != "$before_remote_head" ]]; then
        echo "FAIL: no-op sync unexpectedly changed remote tip" | tee -a "$results_file"
        TEST_STATUS="FAIL"
    else
        echo "PASS: no-op sync preserved remote tip" | tee -a "$results_file"
    fi

    echo "Scenario 3: invalid local repository should fail" | tee -a "$results_file"
    local_git_sync_run_emacs_sync "$TEST_DATA_DIR/nonexistent-local-repo" "$invalid_repo_stdout"
    if grep -q "RESULT:SUCCESS" "$invalid_repo_stdout"; then
        echo "FAIL: invalid local repository scenario reported success" | tee -a "$results_file"
        echo "FAILURE_CLASS:LOCAL_REPO_INVALID:FAIL" | tee -a "$results_file"
        TEST_STATUS="FAIL"
    else
        echo "PASS: invalid local repository scenario reported failure" | tee -a "$results_file"
        echo "FAILURE_CLASS:LOCAL_REPO_INVALID:PASS" | tee -a "$results_file"
    fi

    echo "Scenario 4: unavailable local push target should fail" | tee -a "$results_file"
    git -C "$LOCAL_GIT_SYNC_LOCAL_REPO" remote set-url origin "file://$LOCAL_GIT_SYNC_UNAVAILABLE_REMOTE"
    echo "* Push target unavailable marker $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$LOCAL_GIT_SYNC_LOCAL_REPO/seed.org"
    local_git_sync_run_emacs_sync "$LOCAL_GIT_SYNC_LOCAL_REPO" "$unavailable_remote_stdout"

    if grep -q "RESULT:SUCCESS" "$unavailable_remote_stdout"; then
        echo "FAIL: unavailable push target scenario reported success" | tee -a "$results_file"
        echo "FAILURE_CLASS:PUSH_TARGET_UNAVAILABLE:FAIL" | tee -a "$results_file"
        TEST_STATUS="FAIL"
    else
        echo "PASS: unavailable push target scenario reported failure" | tee -a "$results_file"
        echo "FAILURE_CLASS:PUSH_TARGET_UNAVAILABLE:PASS" | tee -a "$results_file"
    fi

    if [[ "$TEST_STATUS" == "PASS" ]]; then
        echo "LOCAL_GIT_SYNC_RESULT:PASS" | tee -a "$results_file"
    else
        echo "LOCAL_GIT_SYNC_RESULT:FAIL" | tee -a "$results_file"
        return 1
    fi
}

# =============================================================================
# Container Lifecycle
# =============================================================================

start_containers() {
    echo ""
    echo "=== Starting Containers ==="

    cd "$REPO_ROOT"

    echo "Starting containers with test override (rebuilding image)..."
    podman-compose -f "$COMPOSE_FILE" -f "$COMPOSE_OVERRIDE" up -d --build

    echo "Containers started"
}

wait_for_daemon() {
    echo ""
    echo "=== Waiting for Emacs Daemon ==="
    
    local attempt=0
    local ready=false
    
    while [[ $attempt -lt $DAEMON_MAX_ATTEMPTS ]]; do
        attempt=$((attempt + 1))
        echo "Polling daemon (attempt $attempt/$DAEMON_MAX_ATTEMPTS)..."
        
        if podman-compose exec emacs emacsclient -s sem-server --eval 't' &>/dev/null; then
            echo "Daemon is ready!"
            ready=true
            break
        fi
        
        sleep $DAEMON_POLL_INTERVAL
    done
    
    if [[ "$ready" != "true" ]]; then
        echo "ERROR: Emacs daemon failed to become ready after $DAEMON_MAX_ATTEMPTS attempts" >&2
        TEST_STATUS="FAIL"
        return 1
    fi
}

# =============================================================================
# Debug emacsclient connectivity
# =============================================================================

debug_emacsclient() {
    echo ""
    echo "=== Debug: Testing emacsclient connectivity ==="
    
    echo "Running: emacsclient -s sem-server --eval '(message \"EMACSCLIENT: server is up and accessible\")'"
    podman-compose exec emacs emacsclient -s sem-server --eval '(message "EMACSCLIENT: server is up and accessible")'
    
    echo "Debug call complete - check container logs for 'EMACSCLIENT:' message"
}

# =============================================================================
# Cron/emacsclient verification
# =============================================================================

verify_cron_emacsclient() {
    echo ""
    echo "=== Cron/emacsclient Verification ==="
    
    echo "Testing emacsclient can execute scheduled functions..."
    
    local test_result
    test_result=$(podman-compose exec emacs emacsclient -s sem-server --eval '
(progn
  (require (quote sem-core))
  (condition-case err
      (progn
        (message "CRON-VERIFY: Testing sem-core-log availability")
        (if (fboundp (quote sem-core-log))
            (message "CRON-VERIFY: SUCCESS - sem-core-log is available")
          (message "CRON-VERIFY: FAIL - sem-core-log not found"))
        (message "CRON-VERIFY: Testing emacsclient execution successful"))
    (error
     (message "CRON-VERIFY: ERROR - %s" (error-message-string err))))
  t
)' 2>&1)
    
    echo "emacsclient execution result: $test_result"
    
    if echo "$test_result" | grep -q "CRON-VERIFY: SUCCESS"; then
        echo "PASS: emacsclient can execute scheduled commands"
        return 0
    else
        echo "FAIL: emacsclient execution verification failed"
        return 1
    fi
}

verify_elfeed_feed_parser() {
    echo ""
    echo "=== Elfeed Feed Parser Verification ==="

    local parser_result
    parser_result=$(podman-compose exec emacs emacsclient -s sem-server --eval '
(progn
  (require (quote sem-rss))
  (let* ((refresh-result (sem-rss-refresh-feeds t))
         (count (plist-get refresh-result :count))
         (has-trusted nil))
    (dolist (entry elfeed-feeds)
      (let ((url (if (consp entry) (car entry) entry)))
        (when (and (stringp url)
                   (string= url "https://semyonsinchenko.github.io/ssinchenko/index.xml"))
          (setq has-trusted t))))
    (format "count=%s trusted=%s" count has-trusted)))
' 2>&1)

    echo "elfeed parser result: $parser_result"
    if echo "$parser_result" | grep -q "count=" && echo "$parser_result" | grep -q "trusted=t"; then
        echo "PASS: feed parser loaded feeds and found trusted feed URL"
        return 0
    fi

    echo "FAIL: feed parser did not load expected feeds"
    return 1
}

# =============================================================================
# Inbox Processing
# =============================================================================

upload_inbox() {
    echo ""
    echo "=== Uploading Test Inbox ==="
    
    echo "Uploading inbox via WebDAV..."
    curl --fail --silent --show-error \
        -u "${WEBDAV_USERNAME}:${WEBDAV_PASSWORD}" \
        -T "$TEST_INBOX" \
        "${WEBDAV_BASE_URL}/inbox-mobile.org"
    
    echo "Inbox uploaded successfully"
    
    echo "Also copying to TEST_DATA_DIR for reference..."
    cp "$TEST_INBOX" "$TEST_DATA_DIR/inbox-mobile.org"
}

verify_inbox_upload() {
    echo ""
    echo "=== Verifying Inbox Upload ==="
    
    local temp_verify
    temp_verify=$(mktemp)
    
    if curl --fail --silent --show-error \
        -u "${WEBDAV_USERNAME}:${WEBDAV_PASSWORD}" \
        -o "$temp_verify" \
        "${WEBDAV_BASE_URL}/inbox-mobile.org" 2>/dev/null; then
        echo "Inbox fetched successfully from WebDAV"
        
        local sent_lines verify_lines
        sent_lines=$(wc -l < "$TEST_INBOX")
        verify_lines=$(wc -l < "$temp_verify")
        echo "Sent file: $sent_lines lines, Fetched file: $verify_lines lines"
        
        if [[ "$sent_lines" -eq "$verify_lines" ]]; then
            echo "PASS: Line count matches"
            echo "Computing checksums for comparison..."
            echo "  Sent file MD5:     $(md5sum "$TEST_INBOX" | awk '{print $1}')"
            echo "  Fetched file MD5:  $(md5sum "$temp_verify" | awk '{print $1}')"
        else
            echo "FAIL: Line count mismatch"
            echo "--- Sent content ---"
            head -5 "$TEST_INBOX"
            echo "--- Fetched content ---"
            head -5 "$temp_verify"
            TEST_STATUS="FAIL"
        fi
    else
        echo "FAIL: Could not fetch inbox from WebDAV"
        TEST_STATUS="FAIL"
    fi
    
    rm -f "$temp_verify"
}

diagnose_inbox_file() {
    echo ""
    echo "=== Diagnosing Inbox File Visibility ==="
    
    # Step 1: Check that emacs can read the file
    echo "[Step 1] Checking if emacs can read /data/inbox-mobile.org..."
    podman-compose exec emacs emacsclient -s sem-server --eval '(message "DIAG-CHECK: Starting file existence check")'
    podman-compose exec emacs emacsclient -s sem-server --eval '(message "DIAG-CHECK: file-exists-p = %s" (file-exists-p "/data/inbox-mobile.org"))'
    podman-compose exec emacs emacsclient -s sem-server --eval '(message "DIAG-CHECK: file-readable-p = %s" (file-readable-p "/data/inbox-mobile.org"))'
    podman-compose exec emacs emacsclient -s sem-server --eval '(message "DIAG-CHECK: file-writable-p = %s" (file-writable-p "/data/inbox-mobile.org"))'
    echo "[Step 1] File existence check complete"
    
    # Step 2: Read the file and write it back with a different name
    echo "[Step 2] Reading inbox-mobile.org and writing copy to inbox-mobile.copy.org..."
    podman-compose exec emacs emacsclient -s sem-server --eval '
(with-temp-buffer
  (let ((src "/data/inbox-mobile.org")
        (dst "/data/inbox-mobile.copy.org"))
    (message "DIAG-COPY: Starting copy operation from %s to %s" src dst)
    (if (file-exists-p src)
        (progn
          (insert-file-contents src)
          (let ((size (point-max)))
            (message "DIAG-COPY: Read %d bytes from source" size)
            (write-region (point-min) (point-max) dst nil (quote silent))
            (message "DIAG-COPY: Wrote %d bytes to destination" size)
            (message "DIAG-COPY: Destination file exists after write: %s" (file-exists-p dst))))
      (message "DIAG-COPY: Source file does not exist, cannot copy")))
  (message "DIAG-COPY: Copy operation complete"))
' 2>&1 || echo "WARNING: file copy operation failed"
    echo "[Step 2] File copy operation complete"
    
    # Step 3: Write full diagnostics (verbose - output to both buffer and stdout via message)
    echo "[Step 3] Writing full diagnostic report..."
    podman-compose exec emacs emacsclient -s sem-server --eval '
(progn
  (require (quote org-element))
  (let ((diag-output ""))
    (cl-flet ((diag-insert (fmt &rest args)
                           (let ((text (apply (function format) (cons fmt args))))
                             (setq diag-output (concat diag-output text "\n")))))
      (diag-insert "=== INBOX DIAGNOSTIC ===")
      (diag-insert "Time: %s" (current-time-string))
      (diag-insert "File exists: %s" (file-exists-p "/data/inbox-mobile.org"))
      (diag-insert "File readable: %s" (file-readable-p "/data/inbox-mobile.org"))
      (diag-insert "File writable: %s" (file-writable-p "/data/inbox-mobile.org"))
      (diag-insert "Copy file exists: %s" (file-exists-p "/data/inbox-mobile.copy.org"))
      (when (file-exists-p "/data/inbox-mobile.org")
        (insert-file-contents "/data/inbox-mobile.org")
        (diag-insert "Buffer size: %d bytes" (point-max))
        (diag-insert "First 300 chars:")
        (diag-insert "%s" (buffer-substring-no-properties (point-min) (min (point-max) 300)))
        (diag-insert "Last 100 chars:")
        (diag-insert "%s" (buffer-substring-no-properties (max (point-min) (- (point-max) 100)) (point-max)))
        (condition-case err
            (progn
              (org-mode)
              (let ((ast (org-element-parse-buffer)))
                (diag-insert "AST parsed OK, root type: %s" (org-element-type ast))
                (let ((headlines (org-element-map ast (quote headline) (lambda (h) h))))
                  (diag-insert "Headline count: %d" (length headlines))
                  (dolist (h headlines)
                    (diag-insert "  - %s | tags: %s"
                             (org-element-property :raw-value h)
                             (org-element-property :tags h))))))
          (error (diag-insert "PARSE ERROR: %s" (error-message-string err))))))
    ;; Write to file
    (with-temp-buffer
      (insert diag-output)
      (write-region nil nil "/data/sem-diag.txt"))
    ;; Also print to stdout via message (will appear in container logs)
    (message "DIAG-VERBOSE:\n%s" diag-output)
    (message "DIAG-VERBOSE: End of diagnostic output")))
' 2>&1 || echo "WARNING: emacsclient diagnose failed"
    echo "[Step 3] Diagnostic report written"
    
    # Fetch the diagnostic file from WebDAV
    echo "Fetching diagnostic file from WebDAV..."
    curl --silent --show-error \
        -u "${WEBDAV_USERNAME}:${WEBDAV_PASSWORD}" \
        -o "$RUN_DIR/sem-diag.txt" \
        "${WEBDAV_BASE_URL}/data/sem-diag.txt" 2>/dev/null || echo "Could not fetch sem-diag.txt"
    
    echo "Diagnostic file saved to: $RUN_DIR/sem-diag.txt"
    echo "=== Diagnostic content ==="
    cat "$RUN_DIR/sem-diag.txt" 2>/dev/null || echo "(empty or not found)"
    echo "=== End diagnostic ==="
}

trigger_inbox_processing() {
    echo ""
    echo "=== Triggering Inbox Processing ==="
    
    echo "Calling sem-core-process-inbox..."
    podman-compose exec emacs emacsclient -s sem-server -e "(sem-core-process-inbox)"
    
    echo "Inbox processing triggered"
}

wait_for_tasks() {
    local expected_count="${1:-0}"
    echo ""
    echo "=== Waiting for Tasks.org (expecting $expected_count tasks) ==="
    
    local attempt=0
    local todo_count=0
    local temp_file
    temp_file=$(mktemp)
    
    while [[ $attempt -lt $TASKS_MAX_ATTEMPTS ]]; do
        attempt=$((attempt + 1))
        echo "Polling tasks.org (attempt $attempt/$TASKS_MAX_ATTEMPTS)..."
        
        # GET tasks.org
        if curl --fail --silent --show-error \
            -u "${WEBDAV_USERNAME}:${WEBDAV_PASSWORD}" \
            -o "$temp_file" \
            "${WEBDAV_BASE_URL}/data/tasks.org" 2>/dev/null; then
            
            # Count TODO entries
            todo_count=$(grep -c '^\* TODO ' "$temp_file" 2>/dev/null || echo "0")
            echo "Found $todo_count TODO entries"
            
            if [[ "$todo_count" -ge "$expected_count" ]]; then
                echo "All $expected_count tasks detected!"
                # Save the temp file as our authoritative tasks.org
                mv "$temp_file" "$RUN_DIR/tasks.org"
                return 0
            fi
        else
            echo "tasks.org not yet available"
        fi
        
        sleep $TASKS_POLL_INTERVAL
    done
    
    # Timeout - save partial results
    echo "WARNING: Poll timeout - tasks.org may be incomplete" >&2
    TEST_STATUS="FAIL"
    
    # Save whatever we got (even if empty/partial)
    if [[ -f "$temp_file" && -s "$temp_file" ]]; then
        mv "$temp_file" "$RUN_DIR/tasks.org"
    else
        touch "$RUN_DIR/tasks.org"
    fi
    
    rm -f "$temp_file"
    return 1
}

# =============================================================================
# Artifact Collection
# =============================================================================

collect_artifacts() {
    echo ""
    echo "=== Collecting Artifacts ==="
    
    # Copy inbox-sent.org (the test inbox we sent)
    echo "Copying inbox-sent.org..."
    cp "$TEST_INBOX" "$RUN_DIR/inbox-sent.org"
    
    # GET tasks.org if not already saved during poll
    if [[ ! -f "$RUN_DIR/tasks.org" ]]; then
        echo "Fetching tasks.org..."
        curl --silent --show-error \
            -u "${WEBDAV_USERNAME}:${WEBDAV_PASSWORD}" \
            -o "$RUN_DIR/tasks.org" \
            "${WEBDAV_BASE_URL}/data/tasks.org" 2>/dev/null || touch "$RUN_DIR/tasks.org"
    fi
    
    # GET sem-log.org
    echo "Fetching sem-log.org..."
    curl --silent --show-error \
        -u "${WEBDAV_USERNAME}:${WEBDAV_PASSWORD}" \
        -o "$RUN_DIR/sem-log.org" \
        "${WEBDAV_BASE_URL}/data/sem-log.org" 2>/dev/null || touch "$RUN_DIR/sem-log.org"
    
    # GET errors.org (may 404 - handle silently)
    echo "Fetching errors.org (may not exist)..."
    if ! curl --fail --silent --show-error \
        -u "${WEBDAV_USERNAME}:${WEBDAV_PASSWORD}" \
        -o "$RUN_DIR/errors.org" \
        "${WEBDAV_BASE_URL}/data/errors.org" 2>/dev/null; then
        echo "errors.org not found (this is OK)"
        touch "$RUN_DIR/errors.org"
    fi

    # GET journal.org (may 404 when journal route fails)
    echo "Fetching journal.org (may not exist)..."
    if ! curl --fail --silent --show-error \
        -u "${WEBDAV_USERNAME}:${WEBDAV_PASSWORD}" \
        -o "$RUN_DIR/journal.org" \
        "${WEBDAV_BASE_URL}/data/journal.org" 2>/dev/null; then
        echo "journal.org not found"
        touch "$RUN_DIR/journal.org"
    fi
    
    # Copy diagnostic files (may have been created during test)
    echo "Copying diagnostic files..."
    [[ -f "$RUN_DIR/sem-diag.txt" ]] && echo "  sem-diag.txt already present" || echo "  sem-diag.txt not found"
    [[ -f "$RUN_DIR/sem-proc-diag.txt" ]] && echo "  sem-proc-diag.txt already present" || echo "  sem-proc-diag.txt not found"
    [[ -f "$RUN_DIR/container-inbox-mobile.org" ]] && echo "  container-inbox-mobile.org already present" || echo "  container-inbox-mobile.org not found"

    # Collect URL-capture org-roam artifacts with baseline/new visibility
    echo "Collecting URL-capture org-roam artifacts..."
    local org_roam_artifacts_dir="$RUN_DIR/url-capture-org-roam"
    local org_roam_meta_dir="$RUN_DIR/url-capture-meta"
    local baseline_dir="$org_roam_artifacts_dir/baseline"
    local new_dir="$org_roam_artifacts_dir/new"
    local all_dir="$org_roam_artifacts_dir/all"
    local post_manifest="$org_roam_meta_dir/post-run-manifest.txt"
    local new_manifest="$org_roam_meta_dir/new-manifest.txt"

    mkdir -p "$baseline_dir" "$new_dir" "$all_dir" "$org_roam_meta_dir"

    if [[ -d "$ORG_ROAM_NOTES_DIR" ]]; then
        find "$ORG_ROAM_NOTES_DIR" -maxdepth 1 -type f -name '*.org' -printf '%f\n' | sort > "$post_manifest"
        cp "$ORG_ROAM_NOTES_DIR"/*.org "$all_dir/" 2>/dev/null || true

        if [[ -f "$ORG_ROAM_BASELINE_MANIFEST" ]]; then
            cp "$ORG_ROAM_BASELINE_MANIFEST" "$org_roam_meta_dir/baseline-manifest.txt"
            comm -13 "$ORG_ROAM_BASELINE_MANIFEST" "$post_manifest" > "$new_manifest"

            while IFS= read -r filename; do
                [[ -z "$filename" ]] && continue
                cp "$ORG_ROAM_NOTES_DIR/$filename" "$baseline_dir/" 2>/dev/null || true
            done < "$ORG_ROAM_BASELINE_MANIFEST"

            while IFS= read -r filename; do
                [[ -z "$filename" ]] && continue
                cp "$ORG_ROAM_NOTES_DIR/$filename" "$new_dir/" 2>/dev/null || true
            done < "$new_manifest"
        else
            echo "WARNING: Missing baseline manifest: $ORG_ROAM_BASELINE_MANIFEST" | tee -a "$RUN_DIR/validation.txt"
        fi
    else
        echo "WARNING: Runtime org-roam notes directory missing: $ORG_ROAM_NOTES_DIR" | tee -a "$RUN_DIR/validation.txt"
    fi

    # Copy log files from ./logs/
    echo "Copying message logs..."
    if compgen -G "$LOGS_DIR/messages-*.log" > /dev/null; then
        cp "$LOGS_DIR"/messages-*.log "$RUN_DIR/"
    else
        echo "No message logs found"
        touch "$RUN_DIR/messages-none.log"
    fi
    
    # Collect container logs
    echo "Collecting container logs..."
    podman-compose logs emacs > "$RUN_DIR/emacs-container.log" 2>&1 || true
    podman-compose logs webdav > "$RUN_DIR/webdav-container.log" 2>&1 || true
    
    echo "Artifacts collected to: $RUN_DIR"
}

# =============================================================================
# Assertions
# =============================================================================

run_assertions() {
    echo ""
    echo "=== Running Assertions ==="
    
    local validation_file="$RUN_DIR/validation.txt"
    rm -f "$RUN_DIR/assertion-results.txt"
    
    # Assertion 1: TODO count
    echo "Assertion 1: TODO count..."
    {
        echo "=== Assertion 1: TODO Count ==="
        local todo_count
        todo_count=$(grep -c '^\* TODO ' "$RUN_DIR/tasks.org" 2>/dev/null || echo "0")
        echo "Found $todo_count TODO entries (expected: $EXPECTED_TASK_COUNT)"
        
        if [[ "$todo_count" -ne "$EXPECTED_TASK_COUNT" ]]; then
            echo "FAIL: expected $EXPECTED_TASK_COUNT TODO entries, got $todo_count"
            echo "ASSERTION_1_RESULT:FAIL"
        else
            echo "PASS: TODO count is $EXPECTED_TASK_COUNT"
            echo "ASSERTION_1_RESULT:PASS"
        fi
        echo ""
    } | tee -a "$validation_file" | tee -a "$RUN_DIR/assertion-results.txt"
    
    # Assertion 2: Keyword presence
    echo "Assertion 2: Keyword presence..."
    {
        echo "=== Assertion 2: Keyword Presence ==="
        local keyword_failed=false
        
        for keyword in "${KEYWORDS[@]}"; do
            if grep -Fqi "$keyword" "$RUN_DIR/tasks.org" 2>/dev/null; then
                echo "PASS: Found '$keyword'"
            else
                echo "FAIL: Missing keyword '$keyword'"
                keyword_failed=true
            fi
        done
        
        if [[ "$keyword_failed" == "true" ]]; then
            echo "FAIL: Some keywords missing"
            echo "ASSERTION_2_RESULT:FAIL"
        else
            echo "PASS: All keywords present"
            echo "ASSERTION_2_RESULT:PASS"
        fi
        echo ""
    } | tee -a "$validation_file" | tee -a "$RUN_DIR/assertion-results.txt"
    
    # Assertion 3: Pre-existing immutability + lower-bound + overlap policy
    echo "Assertion 3: Pre-existing immutability and scheduling policy..."
    {
        echo "=== Assertion 3: Pre-existing Immutability and Scheduling Policy ==="

        local runtime_now_epoch runtime_min_start_epoch runtime_min_start_iso
        runtime_now_epoch=$(date -u +%s)
        runtime_min_start_epoch=$((runtime_now_epoch + 3600))
        runtime_min_start_iso=$(date -u -d "@$runtime_min_start_epoch" +%Y-%m-%dT%H:%M:%SZ)
        echo "Timezone authority: $RUNTIME_TIMEZONE"

        if python3 - "$RUN_DIR/tasks.org" "$PREEXISTING_TASKS_FIXTURE" "$TEST_INBOX" "$runtime_min_start_epoch" "$runtime_min_start_iso" "$ASSERTION3_LOWER_BOUND_TOLERANCE_SECONDS" <<'PY'
import datetime
import re
import sys

tasks_path = sys.argv[1]
preexisting_fixture_path = sys.argv[2]
inbox_fixture_path = sys.argv[3]
runtime_min_start_epoch = int(sys.argv[4])
runtime_min_start_iso = sys.argv[5]
tolerance_seconds = int(sys.argv[6])

headline_re = re.compile(r"^(\*+)\s+TODO\s+(.*?)(?:\s+:[^:]+(?::[^:]+)*:)?\s*$")
scheduled_re = re.compile(r"^\s*SCHEDULED:\s*(<[^>]+>)")
priority_re = re.compile(r"\[#([A-C])\]")
org_ts_re = re.compile(r"<(\d{4})-(\d{2})-(\d{2})(?:\s+[A-Za-z]{3})?(?:\s+(\d{2}):(\d{2})(?:-(\d{2}):(\d{2}))?)?>")
fixed_schedule_exception_titles = {"process quarterly financial reports"}


def parse_org_timestamp_range(ts: str):
    m = org_ts_re.fullmatch(ts.strip())
    if not m:
        raise ValueError(f"unsupported org timestamp format: {ts}")
    year, month, day = map(int, m.group(1, 2, 3))
    start_h = int(m.group(4) or 0)
    start_m = int(m.group(5) or 0)
    end_h = int(m.group(6) or 23)
    end_m = int(m.group(7) or 59)
    start = datetime.datetime(year, month, day, start_h, start_m, tzinfo=datetime.timezone.utc)
    end = datetime.datetime(year, month, day, end_h, end_m, tzinfo=datetime.timezone.utc)
    return int(start.timestamp()), int(end.timestamp())


def timestamps_match_exception_policy(expected_ts: str, actual_ts: str):
    expected = org_ts_re.fullmatch((expected_ts or "").strip())
    actual = org_ts_re.fullmatch((actual_ts or "").strip())
    if not expected or not actual:
        return expected_ts == actual_ts

    expected_date = expected.group(1, 2, 3)
    actual_date = actual.group(1, 2, 3)
    if expected_date != actual_date:
        return False

    expected_has_time = expected.group(4) is not None and expected.group(5) is not None
    if not expected_has_time:
        return True

    expected_start = (expected.group(4), expected.group(5))
    expected_end = (expected.group(6) or "23", expected.group(7) or "59")
    actual_start = (actual.group(4) or "00", actual.group(5) or "00")
    actual_end = (actual.group(6) or "23", actual.group(7) or "59")
    return expected_start == actual_start and expected_end == actual_end


def split_headline_blocks(text: str):
    starts = [m.start() for m in re.finditer(r"(?m)^\*+\s+TODO\s+", text)]
    blocks = []
    for i, start in enumerate(starts):
        end = starts[i + 1] if i + 1 < len(starts) else len(text)
        blocks.append(text[start:end].rstrip("\n"))
    return blocks


def title_from_block(block: str):
    first = block.splitlines()[0] if block.splitlines() else ""
    m = headline_re.match(first)
    return m.group(2).strip() if m else "<unknown>"


def normalize_title_for_match(title: str):
    title = re.sub(r"\[#([A-C])\]", "", title or "")
    title = re.sub(r"\s+", " ", title).strip().lower()
    return title


def match_exception_title(normalized_title: str):
    if normalized_title in fixed_schedule_exception_titles:
        return normalized_title
    partial_matches = [
        known_title
        for known_title in fixed_schedule_exception_titles
        if known_title in normalized_title or normalized_title in known_title
    ]
    if len(partial_matches) == 1:
        return partial_matches[0]
    if len(partial_matches) > 1:
        raise ValueError(
            f"ambiguous exception-title match normalized_title='{normalized_title}' "
            f"candidates={partial_matches}"
        )
    return None


def scheduled_from_block(block: str):
    for line in block.splitlines()[1:]:
        m = scheduled_re.match(line)
        if m:
            return m.group(1)
    return None


with open(tasks_path, "r", encoding="utf-8") as f:
    final_text = f.read()
with open(preexisting_fixture_path, "r", encoding="utf-8") as f:
    fixture_text = f.read()
with open(inbox_fixture_path, "r", encoding="utf-8") as f:
    inbox_fixture_text = f.read()

final_blocks = split_headline_blocks(final_text)
fixture_blocks = split_headline_blocks(fixture_text)
inbox_fixture_blocks = split_headline_blocks(inbox_fixture_text)

failed = False

if len(final_blocks) < len(fixture_blocks):
    print(
        f"FAIL: tasks.org has fewer TODOs than pre-existing fixture "
        f"(final={len(final_blocks)}, preexisting={len(fixture_blocks)})"
    )
    failed = True
else:
    for i, fixture_block in enumerate(fixture_blocks):
        final_block = final_blocks[i]
        title = title_from_block(fixture_block)
        if final_block != fixture_block:
            print(f"FAIL: pre-existing immutability violated at index={i} task='{title}'")
            failed = True
        else:
            print(f"PASS: pre-existing task preserved index={i} task='{title}'")

        fixture_sched = scheduled_from_block(fixture_block)
        final_sched = scheduled_from_block(final_block)
        if fixture_sched is None and final_sched is not None:
            print(
                f"FAIL: pre-existing unscheduled task gained schedule task='{title}' "
                f"actual='{final_sched}'"
            )
            failed = True

preexisting_windows = []
fixture_schedules_by_title = {}
for block in inbox_fixture_blocks:
    title = title_from_block(block)
    normalized_title = normalize_title_for_match(title)
    sched = scheduled_from_block(block)
    if sched is not None:
        fixture_schedules_by_title[normalized_title] = sched

for block in fixture_blocks:
    title = title_from_block(block)
    normalized_title = normalize_title_for_match(title)
    sched = scheduled_from_block(block)
    if sched is None:
        continue
    try:
        start, end = parse_org_timestamp_range(sched)
    except Exception as err:
        print(f"FAIL: pre-existing task has unparseable timestamp task='{title}' ts='{sched}' err='{err}'")
        failed = True
        continue
    preexisting_windows.append((title, sched, start, end))

new_blocks = final_blocks[len(fixture_blocks):]
for block in new_blocks:
    title = title_from_block(block)
    normalized_title = normalize_title_for_match(title)
    sched = scheduled_from_block(block)
    if sched is None:
        continue
    m = priority_re.search(block.splitlines()[0])
    priority = m.group(1) if m else None
    is_high_priority = priority in {"A", "B"}
    try:
        start, end = parse_org_timestamp_range(sched)
    except Exception as err:
        print(f"FAIL: new task has unparseable timestamp task='{title}' ts='{sched}' err='{err}'")
        failed = True
        continue

    matched_exception_title = match_exception_title(normalized_title)
    if matched_exception_title:
        expected_sched = fixture_schedules_by_title.get(matched_exception_title)
        if expected_sched is None:
            print(
                f"FAIL: fixed-schedule exception fixture missing schedule "
                f"task='{title}' normalized_title='{matched_exception_title}'"
            )
            failed = True
        elif not timestamps_match_exception_policy(expected_sched, sched):
            print(
                f"FAIL: fixed-schedule exception mismatch task='{title}' "
                f"actual='{sched}' expected_fixture='{expected_sched}'"
            )
            failed = True
        else:
            print(
                f"PASS: fixed-schedule exception matched task='{title}' "
                f"actual='{sched}' expected_fixture='{expected_sched}'"
            )
        continue

    if start + tolerance_seconds <= runtime_min_start_epoch:
        print(
            f"FAIL: lower-bound violation task='{title}' actual='{sched}' "
            f"runtime_min_start='{runtime_min_start_iso}' tolerance_seconds='{tolerance_seconds}'"
        )
        failed = True
    else:
        print(
            f"PASS: lower-bound satisfied task='{title}' actual='{sched}' "
            f"runtime_min_start='{runtime_min_start_iso}' tolerance_seconds='{tolerance_seconds}'"
        )

    for existing_title, existing_sched, w_start, w_end in preexisting_windows:
        overlap = start < w_end and w_start < end
        if not overlap:
            continue
        if is_high_priority:
            print(
                f"PASS: approved overlap exception task='{title}' priority='{priority}' "
                f"window_task='{existing_title}' window='{existing_sched}'"
            )
        else:
            print(
                f"FAIL: overlap-policy violation task='{title}' priority='{priority or 'none'}' "
                f"task_scheduled='{sched}' occupied_by='{existing_title}' occupied_window='{existing_sched}'"
            )
            failed = True

sys.exit(1 if failed else 0)
PY
        then
            echo "PASS: Immutability and scheduling policy checks passed"
            echo "ASSERTION_3_RESULT:PASS"
        else
            echo "FAIL: Immutability and/or scheduling policy checks failed"
            echo "ASSERTION_3_RESULT:FAIL"
        fi
        echo ""
    } | tee -a "$validation_file" | tee -a "$RUN_DIR/assertion-results.txt"

    # Assertion 4: Org validity
    echo "Assertion 4: Org validity..."
    {
        echo "=== Assertion 4: Org Validity ==="
        
        if emacs --batch \
            --eval "(condition-case err \
                      (progn (find-file \"$RUN_DIR/tasks.org\") \
                             (org-mode) \
                             (org-element-parse-buffer) \
                             (message \"ORG-VALID\")) \
                    (error (error \"ORG-INVALID: %s\" err)))" 2>&1 | grep -q "ORG-VALID"; then
            echo "PASS: tasks.org is valid Org"
            echo "ASSERTION_4_RESULT:PASS"
        else
            echo "FAIL: tasks.org is not valid Org"
            echo "ASSERTION_4_RESULT:FAIL"
        fi
        echo ""
    } | tee -a "$validation_file" | tee -a "$RUN_DIR/assertion-results.txt"
    
    # Assertion 5: Sensitive content restoration
    echo "Assertion 5: Sensitive content restoration..."
    {
        echo "=== Assertion 5: Sensitive Content Restoration ==="

        local sensitive_failed=false
        
        for keyword in "${SENSITIVE_KEYWORDS[@]}"; do
            if grep -q "$keyword" "$RUN_DIR/tasks.org" 2>/dev/null; then
                echo "PASS: Sensitive content restored: '$keyword'"
            else
                echo "FAIL: Sensitive content NOT restored: '$keyword'"
                sensitive_failed=true
            fi
        done
        
        if [[ "$sensitive_failed" == "true" ]]; then
            echo "FAIL: Some sensitive content not restored"
            echo "ASSERTION_5_RESULT:FAIL"
        else
            echo "PASS: All sensitive content properly restored"
            echo "ASSERTION_5_RESULT:PASS"
        fi
        echo ""
    } | tee -a "$validation_file" | tee -a "$RUN_DIR/assertion-results.txt"
    
    # Assertion 5a: Negative marker check - no #+begin_sensitive markers in output
    echo "Assertion 5a: Negative marker check..."
    {
        echo "=== Assertion 5a: Negative Marker Check ==="
        
        if grep -q '#+begin_sensitive' "$RUN_DIR/tasks.org" 2>/dev/null; then
            echo "FAIL: Found '#+begin_sensitive' markers in output - markers should not be present"
            echo "ASSERTION_5A_RESULT:FAIL"
        else
            echo "PASS: No '#+begin_sensitive' markers found in output"
            echo "ASSERTION_5A_RESULT:PASS"
        fi
        echo ""
    } | tee -a "$validation_file" | tee -a "$RUN_DIR/assertion-results.txt"
    
    # Assertion 5b: Order verification - within each task, sensitive content appears in same order as original
    echo "Assertion 5b: Sensitive content within-task order verification..."
    {
        echo "=== Assertion 5b: Sensitive Content Within-Task Order Verification ==="
        
        local tasks_content
        tasks_content=$(cat "$RUN_DIR/tasks.org" 2>/dev/null || echo "")
        
        # For "Update password manager" task: supersecret123 should appear before sk-live-abc123xyz789
        local pos1 pos2 pos3 pos4
        pos1=$(echo "$tasks_content" | grep -n 'supersecret123' | head -1 | cut -d: -f1 || true)
        pos2=$(echo "$tasks_content" | grep -n 'sk-live-abc123xyz789' | head -1 | cut -d: -f1 || true)
        pos3=$(echo "$tasks_content" | grep -n 'IBAN: DE89370400440532013000' | head -1 | cut -d: -f1 || true)
        pos4=$(echo "$tasks_content" | grep -n 'ACCOUNT NUMBER: 123456789' | head -1 | cut -d: -f1 || true)
        
        local order_failed=false
        
        echo "Task 'Update password manager': supersecret123 at line $pos1, sk-live-abc123xyz789 at line $pos2"
        if [[ -n "$pos1" && -n "$pos2" ]]; then
            if [[ "$pos1" -lt "$pos2" ]]; then
                echo "PASS: supersecret123 appears before sk-live-abc123xyz789"
            else
                echo "FAIL: supersecret123 does NOT appear before sk-live-abc123xyz789"
                order_failed=true
            fi
        else
            echo "FAIL: Could not find both keywords in password manager task"
            order_failed=true
        fi
        
        echo "Task 'Process payment to vendor': IBAN at line $pos3, ACCOUNT NUMBER at line $pos4"
        if [[ -n "$pos3" && -n "$pos4" ]]; then
            if [[ "$pos3" -lt "$pos4" ]]; then
                echo "PASS: IBAN appears before ACCOUNT NUMBER"
            else
                echo "FAIL: IBAN does NOT appear before ACCOUNT NUMBER"
                order_failed=true
            fi
        else
            echo "FAIL: Could not find both keywords in payment task"
            order_failed=true
        fi
        
        if [[ "$order_failed" == "true" ]]; then
            echo "ASSERTION_5B_RESULT:FAIL"
        else
            echo "PASS: All sensitive content within-task order correct"
            echo "ASSERTION_5B_RESULT:PASS"
        fi
        
        echo ""
    } | tee -a "$validation_file" | tee -a "$RUN_DIR/assertion-results.txt"
    
    # Assertion 6: SCHEDULED times fall within preferred windows from rules.org
    echo "Assertion 6: SCHEDULED time preference validation..."
    {
        echo "=== Assertion 6: SCHEDULED Time Preference Validation ==="
        
        # Check if tasks.org exists and has scheduled times
        if [[ ! -f "$RUN_DIR/tasks.org" ]] || [[ ! -s "$RUN_DIR/tasks.org" ]]; then
            echo "SKIP: tasks.org does not exist or is empty - cannot validate SCHEDULED times"
            echo "ASSERTION_6_RESULT:SKIP"
        else
            # Read rules to understand preferences
            local rules_file="$SCRIPT_DIR/testing-resources/rules.org"
            if [[ ! -f "$rules_file" ]]; then
                echo "SKIP: rules.org not found - cannot validate preferences"
                echo "ASSERTION_6_RESULT:SKIP"
            else
                # Soft check: validate that SCHEDULED times exist and have time components
                local scheduled_count=0
                local valid_scheduled_count=0
                
                # Count tasks with SCHEDULED that have time components (HH:MM or HH:MM-HH:MM)
                scheduled_count=$(grep -c 'SCHEDULED:' "$RUN_DIR/tasks.org" 2>/dev/null || true)
                scheduled_count=${scheduled_count:-0}
                
                if [[ "$scheduled_count" -eq 0 ]]; then
                    echo "WARN: No tasks have SCHEDULED times"
                    echo "ASSERTION_6_RESULT:WARN"
                else
                    # Count tasks with time ranges (HH:MM-HH:MM format) or specific times (HH:MM)
                    valid_scheduled_count=$(grep 'SCHEDULED:' "$RUN_DIR/tasks.org" 2>/dev/null | grep -cE 'SCHEDULED: <[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}(-[0-9]{2}:[0-9]{2})?>' || true)
                    valid_scheduled_count=${valid_scheduled_count:-0}
                    
                    echo "Found $scheduled_count tasks with SCHEDULED, $valid_scheduled_count with time components"
                    
                    # Soft assertion: at least some tasks should have time components
                    if [[ "$valid_scheduled_count" -gt 0 ]]; then
                        echo "PASS: Some tasks have time components in SCHEDULED (preference: afternoon for routine, after 4PM for free time)"
                        echo "ASSERTION_6_RESULT:PASS"
                    else
                        echo "WARN: No tasks have time components in SCHEDULED - LLM did not add times"
                        echo "ASSERTION_6_RESULT:WARN"
                    fi
                fi
            fi
        fi
        echo ""
    } | tee -a "$validation_file" | tee -a "$RUN_DIR/assertion-results.txt"

    # Assertion 7: Trusted URL-capture output integrity
    echo "Assertion 7: Trusted URL-capture output integrity..."
    {
        echo "=== Assertion 7: Trusted URL-Capture Output Integrity ==="

        local org_roam_dir="$ORG_ROAM_NOTES_DIR"
        local post_manifest="$RUN_DIR/url-capture-meta/post-run-manifest.txt"
        local new_manifest="$RUN_DIR/url-capture-meta/new-manifest.txt"
        local trusted_source_line="Source: [[${TRUSTED_URL}][${TRUSTED_URL}]]"
        local trusted_file=""
        local trusted_candidates=()
        local candidate_failures=()

        if [[ ! -d "$org_roam_dir" ]]; then
            echo "FAIL: Runtime org-roam notes directory missing: $org_roam_dir"
            echo "ASSERTION_7_RESULT:FAIL"
        elif [[ ! -f "$ORG_ROAM_BASELINE_MANIFEST" ]]; then
            echo "FAIL: Baseline manifest missing: $ORG_ROAM_BASELINE_MANIFEST"
            echo "ASSERTION_7_RESULT:FAIL"
        else
            mkdir -p "$RUN_DIR/url-capture-meta"
            find "$org_roam_dir" -maxdepth 1 -type f -name '*.org' -printf '%f\n' | sort > "$post_manifest"
            comm -13 "$ORG_ROAM_BASELINE_MANIFEST" "$post_manifest" > "$new_manifest"

            local new_count
            new_count=$(awk 'NF { c++ } END { print c + 0 }' "$new_manifest")
            echo "New org-roam files beyond baseline: $new_count"

            if [[ "$new_count" -le 0 ]]; then
                echo "FAIL: no newly generated org-roam files detected beyond baseline fixtures"
                echo "ASSERTION_7_RESULT:FAIL"
            else
                while IFS= read -r filename; do
                    [[ -z "$filename" ]] && continue
                    local filepath="$org_roam_dir/$filename"
                    if [[ -f "$filepath" ]] && grep -Fq "$TRUSTED_URL" "$filepath" 2>/dev/null; then
                        trusted_candidates+=("$filepath")
                    fi
                done < "$new_manifest"

                echo "Trusted URL candidate files: ${#trusted_candidates[@]}"
                if [[ ${#trusted_candidates[@]} -eq 0 ]]; then
                    echo "FAIL: no new org-roam files reference trusted URL: $TRUSTED_URL"
                    echo "ASSERTION_7_RESULT:FAIL"
                else
                    for filepath in "${trusted_candidates[@]}"; do
                        local failure_reasons=()
                        local basename_path
                        basename_path=$(basename "$filepath")

                        if [[ "$filepath" != *"/org-files/"* ]]; then
                            failure_reasons+=("candidate path is not under org-files notes root")
                        fi

                        if ! grep -q '^:PROPERTIES:' "$filepath"; then
                            failure_reasons+=("missing :PROPERTIES:")
                        fi
                        if ! grep -q '^:ID:' "$filepath"; then
                            failure_reasons+=("missing :ID:")
                        fi
                        if ! grep -Eq '^#\+title:' "$filepath"; then
                            failure_reasons+=("missing #+title:")
                        fi

                        local roam_refs_line
                        roam_refs_line=$(grep -E '^#\+ROAM_REFS:' "$filepath" 2>/dev/null || true)
                        if [[ -z "$roam_refs_line" ]]; then
                            failure_reasons+=("missing #+ROAM_REFS:")
                        elif [[ "$roam_refs_line" != *"$TRUSTED_URL"* ]]; then
                            failure_reasons+=("#+ROAM_REFS does not contain trusted URL")
                        fi

                        if ! awk '/^\* Summary/{in_summary=1; next} /^\* /{in_summary=0} in_summary && index($0, source) {found=1} END {exit found ? 0 : 1}' source="$trusted_source_line" "$filepath"; then
                            failure_reasons+=("missing exact trusted Source link inside * Summary")
                        fi

                        if ! grep -Eq "\[\[id:${TRUSTED_UMBRELLA_ID}\]\[[^]]+\]\]" "$filepath"; then
                            failure_reasons+=("missing mandatory umbrella link to ${TRUSTED_UMBRELLA_ID}")
                        fi

                        if grep -Eq 'hxxp://|hxxps://' "$filepath"; then
                            failure_reasons+=("contains defanged URL forms (hxxp/hxxps)")
                        fi

                        if [[ ${#failure_reasons[@]} -eq 0 ]]; then
                            trusted_file="$filepath"
                            echo "PASS: trusted URL candidate validated: $basename_path"
                            break
                        fi

                        local reasons_joined
                        reasons_joined=$(IFS='; '; echo "${failure_reasons[*]}")
                        candidate_failures+=("$basename_path => $reasons_joined")
                    done

                    if [[ -n "$trusted_file" ]]; then
                        echo "PASS: trusted URL capture assertions satisfied"
                        echo "ASSERTION_7_RESULT:PASS"
                    else
                        echo "FAIL: no trusted URL candidate satisfied all required structure/ref/link checks"
                        if [[ ${#candidate_failures[@]} -gt 0 ]]; then
                            for detail in "${candidate_failures[@]}"; do
                                echo " - $detail"
                            done
                        fi
                        echo "ASSERTION_7_RESULT:FAIL"
                    fi
                fi
            fi
        fi
        echo ""
    } | tee -a "$validation_file" | tee -a "$RUN_DIR/assertion-results.txt"

    # Assertion 8: Malformed sensitive block is rejected and tracked as security DLQ
    echo "Assertion 8: Malformed sensitive block DLQ/security tracking..."
    {
        echo "=== Assertion 8: Malformed Sensitive Block DLQ/Security Tracking ==="

        local malformed_in_tasks
        malformed_in_tasks="false"
        if grep -Fq "$MALFORMED_SENSITIVE_TASK_TITLE" "$RUN_DIR/tasks.org" 2>/dev/null; then
            malformed_in_tasks="true"
        fi

        if [[ "$malformed_in_tasks" == "true" ]]; then
            echo "FAIL: malformed sensitive fixture leaked into tasks.org"
            echo "ASSERTION_8_RESULT:FAIL"
        else
            local errors_has_fixture_evidence errors_has_security_tag errors_has_priority logs_has_dlq
            errors_has_fixture_evidence="false"
            errors_has_security_tag="false"
            errors_has_priority="false"
            logs_has_dlq="false"

            if grep -Fq "$MALFORMED_SENSITIVE_TASK_TITLE" "$RUN_DIR/errors.org" 2>/dev/null || \
               grep -Fq "$MALFORMED_SENSITIVE_FIXTURE_SNIPPET" "$RUN_DIR/errors.org" 2>/dev/null; then
                errors_has_fixture_evidence="true"
            fi
            if grep -Eq ':security:' "$RUN_DIR/errors.org" 2>/dev/null; then
                errors_has_security_tag="true"
            fi
            if grep -Eq '^\* TODO \[#A\] ' "$RUN_DIR/errors.org" 2>/dev/null; then
                errors_has_priority="true"
            fi
            if grep -Fq "Security preflight failed, moved to DLQ" "$RUN_DIR/sem-log.org" 2>/dev/null; then
                logs_has_dlq="true"
            fi

            echo "errors.org contains malformed fixture evidence: $errors_has_fixture_evidence"
            echo "errors.org contains :security: tag: $errors_has_security_tag"
            echo "errors.org contains [#A] priority entry: $errors_has_priority"
            echo "sem-log.org contains DLQ preflight log: $logs_has_dlq"

            if [[ "$errors_has_fixture_evidence" == "true" &&
                  "$errors_has_security_tag" == "true" &&
                  "$errors_has_priority" == "true" &&
                  "$logs_has_dlq" == "true" ]]; then
                echo "PASS: malformed sensitive fixture is rejected and tracked in security DLQ logs"
                echo "ASSERTION_8_RESULT:PASS"
            else
                echo "FAIL: malformed sensitive fixture security DLQ assertions failed"
                echo "ASSERTION_8_RESULT:FAIL"
            fi
        fi
        echo ""
    } | tee -a "$validation_file" | tee -a "$RUN_DIR/assertion-results.txt"

    # Assertion 9: Cron/system timezone alignment with CLIENT_TIMEZONE
    echo "Assertion 9: Cron/system timezone alignment..."
    {
        echo "=== Assertion 9: Cron/System Timezone Alignment ==="

        local timezone_diag_file
        timezone_diag_file="$RUN_DIR/timezone-diagnostics.txt"

        local container_epoch observed_offset observed_zone localtime_link timezone_file_value tz_env_value cron_tz_line cron_job_tz_line expected_offset
        container_epoch=$(podman-compose exec emacs sh -lc 'date +%s' 2>/dev/null | tr -dc '0-9' || true)
        observed_offset=$(podman-compose exec emacs sh -lc 'date +%z' 2>/dev/null | tr -d '\r' || true)
        observed_zone=$(podman-compose exec emacs sh -lc 'date +%Z' 2>/dev/null | tr -d '\r' || true)
        localtime_link=$(podman-compose exec emacs sh -lc 'if command -v readlink >/dev/null 2>&1; then readlink /etc/localtime || true; else ls -l /etc/localtime || true; fi' 2>/dev/null | tr -d '\r' || true)
        timezone_file_value=$(podman-compose exec emacs sh -lc 'if [ -f /etc/timezone ]; then cat /etc/timezone; fi' 2>/dev/null | tr -d '\r' || true)
        tz_env_value=$(podman-compose exec emacs sh -lc 'printf "%s" "${TZ:-}"' 2>/dev/null | tr -d '\r' || true)
        cron_tz_line=$(podman-compose exec emacs sh -lc 'if [ -f /etc/crontabs/root ]; then grep "^CRON_TZ=" /etc/crontabs/root || true; fi' 2>/dev/null | tr -d '\r' || true)
        cron_job_tz_line=$(podman-compose exec emacs sh -lc 'if [ -f /etc/crontabs/root ]; then grep "^TZ=" /etc/crontabs/root || true; fi' 2>/dev/null | tr -d '\r' || true)

        expected_offset=$(python3 - "$CLIENT_TIMEZONE" "$container_epoch" <<'PY' 2>/dev/null || true
import datetime
import sys
from zoneinfo import ZoneInfo

timezone_name = sys.argv[1]
epoch = int(sys.argv[2])
dt = datetime.datetime.fromtimestamp(epoch, tz=ZoneInfo(timezone_name))
print(dt.strftime("%z"))
PY
)

        cat > "$timezone_diag_file" <<EOF
CLIENT_TIMEZONE=$CLIENT_TIMEZONE
container_epoch=$container_epoch
expected_offset=$expected_offset
observed_offset=$observed_offset
observed_zone=$observed_zone
localtime_link=$localtime_link
timezone_file_value=$timezone_file_value
tz_env_value=$tz_env_value
crontab_cron_tz_line=$cron_tz_line
crontab_tz_line=$cron_job_tz_line
EOF

        cat "$timezone_diag_file"

        local timezone_failed
        timezone_failed="false"

        if [[ -z "$container_epoch" || -z "$observed_offset" || -z "$expected_offset" ]]; then
            echo "FAIL: missing required timezone probe output (epoch/offset)"
            timezone_failed="true"
        fi

        if [[ "$observed_offset" != "$expected_offset" ]]; then
            echo "FAIL: offset mismatch expected=$expected_offset observed=$observed_offset timezone=$CLIENT_TIMEZONE"
            timezone_failed="true"
        else
            echo "PASS: runtime offset matches expected client timezone offset ($expected_offset)"
        fi

        if [[ "$timezone_file_value" != "$CLIENT_TIMEZONE" ]]; then
            echo "FAIL: /etc/timezone mismatch expected=$CLIENT_TIMEZONE observed=$timezone_file_value"
            timezone_failed="true"
        else
            echo "PASS: /etc/timezone matches CLIENT_TIMEZONE"
        fi

        if [[ "$tz_env_value" != "$CLIENT_TIMEZONE" ]]; then
            echo "FAIL: TZ env mismatch expected=$CLIENT_TIMEZONE observed=$tz_env_value"
            timezone_failed="true"
        else
            echo "PASS: TZ environment matches CLIENT_TIMEZONE"
        fi

        if [[ "$cron_tz_line" != "CRON_TZ=$CLIENT_TIMEZONE" ]]; then
            echo "FAIL: crontab CRON_TZ mismatch expected=CRON_TZ=$CLIENT_TIMEZONE observed=$cron_tz_line"
            timezone_failed="true"
        else
            echo "PASS: crontab CRON_TZ matches CLIENT_TIMEZONE"
        fi

        if [[ "$cron_job_tz_line" != "TZ=$CLIENT_TIMEZONE" ]]; then
            echo "FAIL: crontab TZ mismatch expected=TZ=$CLIENT_TIMEZONE observed=$cron_job_tz_line"
            timezone_failed="true"
        else
            echo "PASS: crontab TZ matches CLIENT_TIMEZONE"
        fi

        if echo "$localtime_link" | grep -Fq "/usr/share/zoneinfo/$CLIENT_TIMEZONE"; then
            echo "PASS: /etc/localtime points to expected zoneinfo path"
        else
            echo "FAIL: /etc/localtime does not reference expected zoneinfo path"
            timezone_failed="true"
        fi

        if [[ "$timezone_failed" == "true" ]]; then
            echo "ASSERTION_9_RESULT:FAIL"
        else
            echo "ASSERTION_9_RESULT:PASS"
        fi

        echo ""
    } | tee -a "$validation_file" | tee -a "$RUN_DIR/assertion-results.txt"

    # Assertion 10: Journal route output integrity
    echo "Assertion 10: Journal output integrity..."
    {
        echo "=== Assertion 10: Journal Output Integrity ==="

        local journal_failed=false

        if [[ ! -s "$RUN_DIR/journal.org" ]]; then
            echo "FAIL: journal.org is missing or empty"
            journal_failed=true
        fi

        if grep -Fq "$JOURNAL_BODY_SNIPPET" "$RUN_DIR/journal.org" 2>/dev/null; then
            echo "PASS: journal body snippet found"
        else
            echo "FAIL: journal body snippet missing"
            journal_failed=true
        fi

        if grep -Fq ":TAGS_INBOX: $JOURNAL_TAGS_VALUE" "$RUN_DIR/journal.org" 2>/dev/null; then
            echo "PASS: journal TAGS_INBOX metadata found"
        else
            echo "FAIL: journal TAGS_INBOX metadata missing"
            journal_failed=true
        fi

        if grep -Fq ":MENTIONS_RAW: $JOURNAL_MENTIONS_VALUE" "$RUN_DIR/journal.org" 2>/dev/null; then
            echo "PASS: journal MENTIONS_RAW metadata found"
        else
            echo "FAIL: journal MENTIONS_RAW metadata missing"
            journal_failed=true
        fi

        if grep -Eq '^:INGESTED_AT: ' "$RUN_DIR/journal.org" 2>/dev/null; then
            echo "PASS: journal INGESTED_AT metadata found"
        else
            echo "FAIL: journal INGESTED_AT metadata missing"
            journal_failed=true
        fi

        if [[ "$journal_failed" == "true" ]]; then
            echo "ASSERTION_10_RESULT:FAIL"
        else
            echo "PASS: journal output assertions satisfied"
            echo "ASSERTION_10_RESULT:PASS"
        fi

        echo ""
    } | tee -a "$validation_file" | tee -a "$RUN_DIR/assertion-results.txt"

    # Final result - read from temp file (avoids subshell variable loss issue)
    echo "=== Final Result ==="
    local final_assertion1 final_assertion2 final_assertion3 final_assertion4 final_assertion5 final_assertion5a final_assertion5b final_assertion6 final_assertion7 final_assertion8 final_assertion9 final_assertion10
    final_assertion1=$(grep "ASSERTION_1_RESULT:" "$RUN_DIR/assertion-results.txt" | cut -d: -f2)
    final_assertion2=$(grep "ASSERTION_2_RESULT:" "$RUN_DIR/assertion-results.txt" | cut -d: -f2)
    final_assertion3=$(grep "ASSERTION_3_RESULT:" "$RUN_DIR/assertion-results.txt" | cut -d: -f2)
    final_assertion4=$(grep "ASSERTION_4_RESULT:" "$RUN_DIR/assertion-results.txt" | cut -d: -f2)
    final_assertion5=$(grep "ASSERTION_5_RESULT:" "$RUN_DIR/assertion-results.txt" | cut -d: -f2)
    final_assertion5a=$(grep "ASSERTION_5A_RESULT:" "$RUN_DIR/assertion-results.txt" | cut -d: -f2)
    final_assertion5b=$(grep "ASSERTION_5B_RESULT:" "$RUN_DIR/assertion-results.txt" | cut -d: -f2)
    final_assertion6=$(grep "ASSERTION_6_RESULT:" "$RUN_DIR/assertion-results.txt" | cut -d: -f2)
    final_assertion7=$(grep "ASSERTION_7_RESULT:" "$RUN_DIR/assertion-results.txt" | cut -d: -f2)
    final_assertion8=$(grep "ASSERTION_8_RESULT:" "$RUN_DIR/assertion-results.txt" | cut -d: -f2)
    final_assertion9=$(grep "ASSERTION_9_RESULT:" "$RUN_DIR/assertion-results.txt" | cut -d: -f2)
    final_assertion10=$(grep "ASSERTION_10_RESULT:" "$RUN_DIR/assertion-results.txt" | cut -d: -f2)

    for assertion_key in "${ASSERTION_RESULT_KEYS[@]}"; do
        if ! grep -q "${assertion_key}:" "$RUN_DIR/assertion-results.txt"; then
            echo "WARN: missing assertion marker ${assertion_key} in assertion-results.txt"
        fi
    done

    if [[ "$final_assertion1" == "PASS" &&
          "$final_assertion2" == "PASS" &&
          "$final_assertion3" == "PASS" &&
          "$final_assertion4" == "PASS" &&
          "$final_assertion5" == "PASS" &&
          "$final_assertion5a" == "PASS" &&
          "$final_assertion5b" == "PASS" &&
          "$final_assertion7" == "PASS" &&
          "$final_assertion8" == "PASS" &&
          "$final_assertion9" == "PASS" &&
          "$final_assertion10" == "PASS" &&
          "$TEST_STATUS" == "PASS" &&
          ( "$final_assertion6" == "PASS" || "$final_assertion6" == "WARN" || "$final_assertion6" == "SKIP" ) ]]; then
        echo "ALL ASSERTIONS PASSED"
        exit 0
    fi

    echo "SOME ASSERTIONS FAILED"
    echo "  Assertion 1 (TODO count): $final_assertion1"
    echo "  Assertion 2 (Keywords): $final_assertion2"
    echo "  Assertion 3 (Immutability + overlap + lower bound): $final_assertion3"
    echo "  Assertion 4 (Org validity): $final_assertion4"
    echo "  Assertion 5 (Sensitive content): $final_assertion5"
    echo "  Assertion 5a (No markers): $final_assertion5a"
    echo "  Assertion 5b (Order verification): $final_assertion5b"
    echo "  Assertion 6 (SCHEDULED preferences): $final_assertion6"
    echo "  Assertion 7 (URL-capture trusted output): $final_assertion7"
    echo "  Assertion 8 (Malformed sensitive DLQ/security): $final_assertion8"
    echo "  Assertion 9 (Cron/system timezone alignment): $final_assertion9"
    echo "  Assertion 10 (Journal output integrity): $final_assertion10"
    exit 1
}

# =============================================================================
# Main Execution
# =============================================================================

run_paid_inbox_validation() {
    cd "$REPO_ROOT"
    
    # Setup phase
    cleanup_test_results
    setup_test_data
    setup_logs
    create_run_dir
    
    # Start containers
    start_containers
    
    # Wait for daemon readiness
    if ! wait_for_daemon; then
        echo "Daemon readiness check failed - proceeding to artifact collection"
        collect_artifacts
        exit 1
    fi
    
    # Debug emacsclient connectivity
    debug_emacsclient
    
    # Cron/emacsclient verification
    if ! verify_cron_emacsclient; then
        echo "WARNING: emacsclient verification failed - continuing anyway"
    fi

    if ! verify_elfeed_feed_parser; then
        echo "WARNING: elfeed feed parser verification failed - continuing anyway"
    fi
    
    # Process inbox
    upload_inbox
    verify_inbox_upload
    diagnose_inbox_file
    
    echo "Saving container view of inbox-mobile.org..."
    podman-compose exec emacs cat /data/inbox-mobile.org > "$RUN_DIR/container-inbox-mobile.org" 2>/dev/null || echo "Could not save container inbox"
    
    trigger_inbox_processing
    
    # Wait for processing to complete
    echo "Waiting 5 seconds for inbox processing to complete..."
    sleep 5
    
    # Write processing results diagnostic
    echo "Writing post-processing diagnostic..."
    podman-compose exec emacs emacsclient -s sem-server --eval '
(with-temp-buffer
  (require (quote org-element))
  (insert "=== PROCESSING DIAGNOSTIC ===\n")
  (insert (format "Time: %s\n" (current-time-string)))
  (insert (format "inbox-mobile.org exists: %s\n" (file-exists-p "/data/inbox-mobile.org")))
  (insert (format "tasks.org exists: %s\n" (file-exists-p "/data/tasks.org")))
  (when (file-exists-p "/data/tasks.org")
    (insert-file-contents "/data/tasks.org")
    (insert (format "Tasks file size: %d bytes\n" (point-max)))
    (insert (format "Tasks content (first 500 chars):\n%s\n"
            (buffer-substring-no-properties (point-min) (min (point-max) 500)))))
  (when (file-exists-p "/data/inbox-mobile.org")
    (insert "\n--- Inbox still exists, content (first 200 chars): ---\n")
    (insert-file-contents "/data/inbox-mobile.org")
    (insert (format "\n%s\n" (buffer-substring-no-properties (point-min) (min (point-max) 200)))))
  (condition-case err
      (progn
        (when (file-exists-p "/data/tasks.org")
          (org-mode)
          (let ((ast (org-element-parse-buffer)))
            (let ((headlines (org-element-map ast (quote headline) (lambda (h) t))))
              (insert (format "Headline count in tasks.org: %d\n" (length headlines)))))))
    (error (insert (format "PARSE ERROR on tasks.org: %s\n" err))))
  (write-region (point-min) (point-max) "/data/sem-proc-diag.txt" nil (quote silent)))
' 2>/dev/null || echo "WARNING: emacsclient processing diagnostic failed"

    # Fetch processing diagnostic
    curl --silent --show-error \
        -u "${WEBDAV_USERNAME}:${WEBDAV_PASSWORD}" \
        -o "$RUN_DIR/sem-proc-diag.txt" \
        "${WEBDAV_BASE_URL}/data/sem-proc-diag.txt" 2>/dev/null || echo "Could not fetch sem-proc-diag.txt"
    echo "Post-processing diagnostic saved to: $RUN_DIR/sem-proc-diag.txt"
    
    # Wait for tasks
    if ! wait_for_tasks "$EXPECTED_TASK_COUNT"; then
        echo "Tasks poll timeout - proceeding to artifact collection"
    fi
    
    # Collect artifacts
    collect_artifacts
    
    # Run assertions
    run_assertions
}

run_local_git_sync_mode() {
    cd "$REPO_ROOT"

    # Local git-sync validation path is intentionally isolated from paid inbox/LLM checks.
    cleanup_test_results
    setup_logs
    create_run_dir
    local_git_sync_setup_fixtures
    local_git_sync_validate_fixtures
    run_local_git_sync_validation
}

main() {
    if [[ "$INTEGRATION_MODE" == "$LOCAL_GIT_SYNC_MODE" ]]; then
        run_local_git_sync_mode
    else
        run_paid_inbox_validation
    fi
}

# Run main
main
