# /etc/profile.d/claude-os.sh: managed by claude-os.
# Belt-and-braces for login shells that miss pam_env (rare, but cheap).
export NO_COLOR=1 CLICOLOR=0
export PAGER=cat GIT_PAGER=cat MANPAGER=cat SYSTEMD_PAGER=
export DEBIAN_FRONTEND=noninteractive
export PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright
