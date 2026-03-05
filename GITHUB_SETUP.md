# GitHub Setup

This repository is intended to manage both:

- Python BLE tools at the repository root
- Android / Flutter app under `ble_led_app/`

## Local Git

If `git` is not on PATH yet, use the Git bundled with Flutter:

```powershell
$env:Path = "C:\src\flutter\bin\mingit\cmd;$env:Path"
git --version
```

To make `git` available in new terminals, reopen the terminal after PATH is updated.

## First-time identity setup

```powershell
git config --global user.name "Your Name"
git config --global user.email "your-email@example.com"
```

## Create the local repository

```powershell
git init -b main
git status
```

## Connect to GitHub

Create an empty GitHub repository first, then run:

```powershell
git remote add origin https://github.com/<account>/<repo>.git
git add .
git commit -m "Initial import"
git push -u origin main
```

## Daily workflow

```powershell
git status
git add .
git commit -m "Describe the change"
git push
```
