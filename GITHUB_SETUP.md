# GitHub Repository Setup Guide

This guide will walk you through creating a GitHub repository for XtMate iOS and configuring it for use with Replit.

## 📋 Prerequisites

- GitHub account ([Sign up here](https://github.com/signup))
- Git installed on your local machine
- Xcode project ready to commit

## 🚀 Step 1: Create GitHub Repository

### Option A: Via GitHub Website

1. **Go to GitHub** and sign in
2. **Click the "+" icon** in the top-right corner → "New repository"
3. **Fill in repository details:**
   - **Repository name**: `xtmate-ios`
   - **Description**: "Field-optimized iOS app for insurance claims management with LiDAR scanning"
   - **Visibility**: Choose **Private** (recommended for proprietary code) or **Public**
   - **DO NOT** initialize with README, .gitignore, or license (we already have these)
4. **Click "Create repository"**

### Option B: Via GitHub CLI

```bash
# Install GitHub CLI if you haven't already
brew install gh

# Authenticate
gh auth login

# Create repository
gh repo create xtmate-ios --private --description "Field-optimized iOS app for insurance claims management"
```

## 🔧 Step 2: Initialize Local Git Repository

Open Terminal and navigate to your Xcode project directory:

```bash
# Navigate to project directory
cd /path/to/your/XtMate/project

# Initialize git repository (if not already done)
git init

# Check status to see which files will be committed
git status

# Add all files (respecting .gitignore)
git add .

# Create initial commit
git commit -m "Initial commit: XtMate iOS app with LiDAR scanning and claims management"
```

## 🔗 Step 3: Link to GitHub

```bash
# Add GitHub as remote origin (replace YOUR_USERNAME with your GitHub username)
git remote add origin https://github.com/YOUR_USERNAME/xtmate-ios.git

# Verify remote was added
git remote -v

# Push to GitHub
git branch -M main
git push -u origin main
```

## 🔐 Step 4: Protect API Keys

**CRITICAL**: Before pushing, ensure your API keys are NOT in the repository!

### Verify .gitignore is Working

```bash
# Check that sensitive files are ignored
git status --ignored

# You should see these files listed as ignored:
# - Secrets.xcconfig
# - APIKeys-Production.swift
# - .env files
```

### If You Accidentally Committed API Keys

```bash
# Remove from git history (BEFORE pushing to GitHub)
git rm --cached APIKeys-Production.swift
git commit -m "Remove accidentally committed API keys"

# If already pushed to GitHub, you'll need to:
# 1. Rotate/regenerate your API keys immediately
# 2. Use git filter-branch or BFG Repo-Cleaner to remove from history
# 3. Force push (dangerous - use with caution)
```

## 📱 Step 5: Set Up for Replit

### Understanding Replit Limitations

⚠️ **Important**: Replit is primarily a web-based development environment and has limitations with iOS development:

- **No Xcode Support**: Replit cannot run Xcode or build iOS apps natively
- **No iOS Simulator**: Cannot test on iOS devices or simulators
- **Swift Support**: Replit does support Swift, but only for command-line/server applications

### Recommended Workflows

#### Option 1: Use Replit for Swift Backend/API (Recommended)

If you're building a backend API for XtMate:

1. **Create separate repository** for backend:
   ```bash
   gh repo create xtmate-api --private
   ```

2. **On Replit**:
   - Click "Create Repl"
   - Choose "Import from GitHub"
   - Select `xtmate-api` repository
   - Choose "Swift" as template

3. **Build API endpoints** in Replit that the iOS app can consume

#### Option 2: Use Replit for Code Review/Editing Only

You can import your iOS repo to Replit just for viewing/editing Swift code (no building):

1. **On Replit** ([replit.com](https://replit.com)):
   - Click "Create Repl"
   - Choose "Import from GitHub"
   - Authenticate with GitHub
   - Select `xtmate-ios` repository
   - Choose "Swift" as language

2. **Edit code** in Replit's editor

3. **Commit changes**:
   - Use Replit's built-in Git panel, or
   - Use the shell: `git commit -am "Update from Replit" && git push`

4. **Pull changes to Xcode**:
   ```bash
   # In your local Xcode project directory
   git pull origin main
   ```

#### Option 3: Use GitHub Codespaces (Recommended for iOS)

GitHub Codespaces provides a better environment for iOS/Swift development:

1. **Go to your GitHub repository**
2. **Click "Code" → "Codespaces" → "Create codespace on main"**
3. **Edit Swift files** in VS Code (web or desktop)
4. **Commit and push** directly from Codespaces

### Replit Configuration Files

If you want to use Replit, create these configuration files:

**.replit** (Replit configuration):
```toml
language = "swift"
run = "echo 'This is an iOS Xcode project. It cannot be built in Replit.'"

[nix]
channel = "stable-22_11"

[deployment]
run = ["sh", "-c", "echo 'This is an iOS project for Xcode'"]
```

**replit.nix** (Nix environment):
```nix
{ pkgs }: {
  deps = [
    pkgs.swift
    pkgs.git
  ];
}
```

## 🔄 Step 6: Workflow for Collaborative Development

### Daily Workflow

```bash
# 1. Pull latest changes before starting work
git pull origin main

# 2. Create a feature branch
git checkout -b feature/add-damage-photos

# 3. Make changes in Xcode

# 4. Commit frequently
git add .
git commit -m "Add photo capture to damage tagging"

# 5. Push your branch
git push origin feature/add-damage-photos

# 6. Create Pull Request on GitHub
# - Go to GitHub repository
# - Click "Pull requests" → "New pull request"
# - Select your branch
# - Add description and request review
```

### Handling Merge Conflicts

```bash
# If your pull fails with conflicts
git pull origin main

# Git will mark conflicts in files like:
# <<<<<<< HEAD
# Your changes
# =======
# Their changes
# >>>>>>> main

# Edit files to resolve conflicts
# Then:
git add .
git commit -m "Resolve merge conflicts"
git push origin feature/your-branch
```

## 🏷️ Step 7: Repository Best Practices

### Use GitHub Issues

Track bugs and features:
1. Go to **Issues** tab
2. Click **New Issue**
3. Add descriptive title and details
4. Assign labels (bug, enhancement, etc.)

### Create Project Board

Organize work:
1. Go to **Projects** tab
2. Click **New Project**
3. Choose "Board" template
4. Create columns: Backlog, In Progress, Review, Done

### Set Up Branch Protection

Protect main branch from accidental changes:
1. Go to **Settings** → **Branches**
2. Add rule for `main` branch
3. Enable:
   - Require pull request reviews
   - Require status checks to pass
   - Require branches to be up to date

### Add Collaborators

1. Go to **Settings** → **Collaborators**
2. Click **Add people**
3. Enter GitHub username or email
4. Choose permission level (Write, Admin)

## 🔒 Security Checklist

- [ ] `.gitignore` includes all API key files
- [ ] No hardcoded secrets in source code
- [ ] API keys loaded from Info.plist or environment
- [ ] Repository is private (if proprietary)
- [ ] Branch protection enabled on `main`
- [ ] Two-factor authentication enabled on GitHub account
- [ ] API keys rotated if accidentally committed
- [ ] Collaborators have appropriate permissions

## 📚 Additional Resources

- [GitHub Documentation](https://docs.github.com)
- [Git Basics Tutorial](https://git-scm.com/book/en/v2/Getting-Started-About-Version-Control)
- [GitHub Codespaces](https://github.com/features/codespaces)
- [Swift on Replit Docs](https://docs.replit.com/programming-ide/getting-started-swift)

## 🆘 Troubleshooting

### "Permission denied (publickey)"

```bash
# Generate SSH key
ssh-keygen -t ed25519 -C "your_email@example.com"

# Add to ssh-agent
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519

# Add public key to GitHub
# Copy key: cat ~/.ssh/id_ed25519.pub
# Go to GitHub Settings → SSH Keys → New SSH Key
# Paste key and save
```

### Large Files Won't Push

```bash
# If you have large assets or binaries
# Use Git LFS (Large File Storage)
git lfs install
git lfs track "*.png"
git lfs track "*.jpg"
git lfs track "*.zip"
git add .gitattributes
git commit -m "Configure Git LFS"
```

### Repository Too Large

```bash
# Remove build artifacts
git rm -r --cached build/
git rm -r --cached DerivedData/
git commit -m "Remove build artifacts"

# Ensure .gitignore is correct
# Then push
git push origin main
```

---

**You're all set!** Your iOS project is now on GitHub and ready for collaboration. 🎉
