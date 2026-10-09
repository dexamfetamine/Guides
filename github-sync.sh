

:: BARE GITHUB REPO TO SYNC DOTFILES BETWEEN MACHINES ::

Step 1: Initial Setup (On Your Main Machine)
Execute these commands to track your home directory as a bare repository:

# 1. Initialize a bare git repository in a hidden folder
git init --bare $HOME/.dotfiles

# 2. Set up an alias to interact with your dotfiles repo
alias dotfiles='/usr/bin/git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME'

# 3. Hide untracked files so 'dotfiles status' doesn't list your entire home directory
dotfiles config --local status.showUntrackedFiles no

# 4. Add the alias to your shell config so it persists
echo "alias dotfiles='/usr/bin/git --git-dir=\$HOME/.dotfiles/ --work-tree=\$HOME'" >> ~/.rc
Now start adding and pushing your configs:


# Add desired config files
dotfiles add ~/.rc
dotfiles add ~/.config/tmux/tmux.conf
dotfiles add ~/.zshrc2q13

# Commit and push to GitHub
dotfiles commit -m "Initial dotfiles commit"
dotfiles remote add origin git@github.com:YOUR_USERNAME/dotfiles.git
dotfiles branch -M main
dotfiles push -u origin main

Step 2: Deploying to a New VM or LXC
On any fresh container or VM, run this single workflow:

# 1. Clone the bare repo directly into your home directory location
git clone --bare git@github.com:YOUR_USERNAME/dotfiles.git $HOME/.dotfiles

# 2. Define the alias for the current session
alias dotfiles='/usr/bin/git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME'

# 3. Checkout the actual files into your home directory
dotfiles checkout
Note on checkout errors: If the fresh system already generated default files (like .rc), checkout will fail to avoid overwriting them.
Simply back up or remove the conflicting files, then run dotfiles checkout again.

Finally, hide untracked files on the new node:
dotfiles config --local status.showUntrackedFiles no

# Daily Workflow
Treat dotfiles exactly like standard git:
- Add changes: dotfiles add ~/.rc
- Check status: dotfiles status
- Save changes: dotfiles commit -m "update prompt"
- Sync down: dotfiles pull