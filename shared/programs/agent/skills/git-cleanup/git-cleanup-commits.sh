#!/bin/bash
# Git Commit Cleanup Helper Script
# Usage: ./git-cleanup-commits.sh [scenario]

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
info() {
    echo -e "${BLUE}ℹ ${NC}$1"
}

success() {
    echo -e "${GREEN}✓ ${NC}$1"
}

warning() {
    echo -e "${YELLOW}⚠ ${NC}$1"
}

error() {
    echo -e "${RED}✗ ${NC}$1"
}

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    error "Not in a git repository"
    exit 1
fi

# Get current branch
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
BASE_BRANCH=${BASE_BRANCH:-main}

info "Current branch: $CURRENT_BRANCH"
info "Base branch: $BASE_BRANCH"

# Check for uncommitted changes
if ! git diff-index --quiet HEAD --; then
    error "You have uncommitted changes. Please commit or stash them first."
    exit 1
fi

# Function: Create backup
create_backup() {
    local backup_name="backup/$CURRENT_BRANCH-$(date +%Y%m%d-%H%M%S)"
    git branch "$backup_name"
    success "Created backup branch: $backup_name"
    echo "$backup_name"
}

# Function: Show commits
show_commits() {
    info "Commits in current branch (since $BASE_BRANCH):"
    echo ""
    git log --oneline --graph "$BASE_BRANCH..HEAD"
    echo ""
    local count=$(git log --oneline "$BASE_BRANCH..HEAD" | wc -l)
    info "Total commits: $count"
}

# Function: Squash all commits into one
squash_all() {
    local count=$(git log --oneline "$BASE_BRANCH..HEAD" | wc -l)

    if [ "$count" -le 1 ]; then
        warning "Only one commit found, nothing to squash"
        return
    fi

    info "Squashing $count commits into 1..."

    # Squash all commits except the first one
    GIT_SEQUENCE_EDITOR="sed -i '2,\$s/^pick/fixup/'" git rebase -i "$BASE_BRANCH"

    success "Squashed $count commits into 1"
}

# Function: Squash N commits
squash_n() {
    local n=$1
    local total=$(git log --oneline "$BASE_BRANCH..HEAD" | wc -l)

    if [ "$n" -ge "$total" ]; then
        error "Cannot squash $n commits, only $total commits available"
        exit 1
    fi

    info "Squashing last $n commits into 1..."

    # Calculate which commits to squash (last n commits)
    local start=$((total - n + 1))
    local end=$total

    GIT_SEQUENCE_EDITOR="sed -i '${start},${end}s/^pick/fixup/'" git rebase -i "$BASE_BRANCH"

    success "Squashed $n commits"
}

# Function: Split last commit
split_last() {
    info "Splitting last commit..."

    git reset --soft HEAD~1

    success "Last commit has been reset (changes are still staged)"
    info "Now you can selectively commit files:"
    echo ""
    git status --short
    echo ""
    info "Use 'git reset HEAD <file>' to unstage files"
    info "Use 'git add <file>' and 'git commit' to create new commits"
}

# Function: Remove file from commits
remove_file() {
    local file=$1

    if [ -z "$file" ]; then
        error "Please specify a file to remove"
        exit 1
    fi

    info "Removing '$file' from all commits..."

    # Check if file exists in any commit
    if ! git log --name-only "$BASE_BRANCH..HEAD" | grep -q "^$file$"; then
        warning "File '$file' not found in any commit"
        return
    fi

    # Use filter-branch to remove file from history
    git filter-branch -f --index-filter "git rm --cached --ignore-unmatch $file" "$BASE_BRANCH..HEAD"

    success "Removed '$file' from all commits"
}

# Function: Interactive mode
interactive_mode() {
    show_commits
    echo ""
    info "What would you like to do?"
    echo "  1) Squash all commits into one"
    echo "  2) Squash last N commits"
    echo "  3) Split last commit"
    echo "  4) Remove a file from all commits"
    echo "  5) Show commits again"
    echo "  6) Cancel"
    echo ""
    read -p "Select option (1-6): " choice

    case $choice in
        1)
            squash_all
            ;;
        2)
            read -p "How many commits to squash? " n
            squash_n "$n"
            ;;
        3)
            split_last
            ;;
        4)
            read -p "Enter file path to remove: " file
            remove_file "$file"
            ;;
        5)
            interactive_mode
            ;;
        6)
            info "Cancelled"
            exit 0
            ;;
        *)
            error "Invalid option"
            exit 1
            ;;
    esac
}

# Main script
main() {
    local scenario=${1:-interactive}

    # Always create backup first
    BACKUP_BRANCH=$(create_backup)

    case $scenario in
        "squash-all")
            show_commits
            squash_all
            ;;
        "squash")
            show_commits
            if [ -z "$2" ]; then
                error "Please specify number of commits to squash"
                exit 1
            fi
            squash_n "$2"
            ;;
        "split")
            split_last
            ;;
        "remove")
            if [ -z "$2" ]; then
                error "Please specify file to remove"
                exit 1
            fi
            remove_file "$2"
            ;;
        "interactive"|"")
            interactive_mode
            ;;
        "help"|"-h"|"--help")
            echo "Git Commit Cleanup Helper"
            echo ""
            echo "Usage: $0 [scenario] [options]"
            echo ""
            echo "Scenarios:"
            echo "  interactive       - Interactive mode (default)"
            echo "  squash-all        - Squash all commits into one"
            echo "  squash N          - Squash last N commits"
            echo "  split             - Split last commit"
            echo "  remove FILE       - Remove file from all commits"
            echo ""
            echo "Examples:"
            echo "  $0                        # Interactive mode"
            echo "  $0 squash-all             # Squash everything"
            echo "  $0 squash 3               # Squash last 3 commits"
            echo "  $0 split                  # Split last commit"
            echo "  $0 remove parallel.log    # Remove file"
            echo ""
            echo "Environment variables:"
            echo "  BASE_BRANCH=main          # Set base branch (default: main)"
            exit 0
            ;;
        *)
            error "Unknown scenario: $scenario"
            echo "Use '$0 help' for usage"
            exit 1
            ;;
    esac

    echo ""
    success "Done! Backup branch: $BACKUP_BRANCH"

    # Show final result
    echo ""
    info "Final commit history:"
    git log --oneline --graph "$BASE_BRANCH..HEAD"

    echo ""
    warning "Review the changes above. If everything looks good, push with:"
    echo "  git push --force-with-lease origin $CURRENT_BRANCH"
    echo ""
    warning "If you want to undo, restore from backup:"
    echo "  git reset --hard $BACKUP_BRANCH"
}

# Run main function
main "$@"
