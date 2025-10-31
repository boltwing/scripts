import os
import shutil
import subprocess
import sys
from datetime import datetime as dt  # not the calculus one

__version__ = "v0.0.4"

# __init__
HOME = os.environ.get("HOME")  # KRYPTO... HOME... TAKE ME HOME...
USB = "R3DSH1FT"
NAME = os.environ.get("LOGNAME")
backupDir = "fromPast"
backupPath = f"/run/media/{NAME}/{USB}/{backupDir}"

# just a test

mustDOs = [
    "dotfiles",
    "musics",
    ".ssh",
    "docs",
]

maybeONEs = [
    "fortress",  # Desktop
    "matrix",  # Downloads
    "mems",  # Pictures + Videos
    "games",
]


def copy(src, dst) -> None:
    def ignoreLocks(_, files):
        return [f for f in files if f == "lock"]

    if not os.path.isdir(src):
        try:
            shutil.copy2(src, dst)
        except FileNotFoundError:
            print(f"SKIPPED MISSING FILE: {src}")
    else:
        try:
            shutil.copytree(src, dst, dirs_exist_ok=True, ignore=ignoreLocks)
        except shutil.Error as e:
            for err in e.args[0]:
                print(f"SKIPPED: {err[0]}")


def ping(name: str, sucess=True) -> None:
    if sucess:
        print(f"BACKED UP {name}")


def consent(msg: str) -> bool:
    while True:
        userInput = input(f"{msg} [Y/n] ").lower()
        if "n" in userInput:
            return False
        if "y" in userInput or not userInput:
            return True


def TIME() -> str | None:
    now = dt.now()
    folderName = now.strftime("%y-%-m-%-d %H%M")
    currentBackup = f"{backupPath}/{folderName}"

    if os.path.isdir(currentBackup):
        print("NOT A MINUTE HAS PASSED...")
        if not consent("YOU SURE YOU WANT TO DO IT AGAIN... OVERWRITE?"):
            sys.exit(0)
        shutil.rmtree(currentBackup)

    return currentBackup


def main():
    cB = TIME()  # currentBackup
    if cB is None:
        sys.exit(0)

    subprocess.run(["mkdir", "-p", cB], check=True)
    stuff = os.listdir(HOME)

    for item in stuff:
        if item in mustDOs:
            copy(f"{HOME}/{item}", f"{cB}/{item}")
            ping(item)

        if item in maybeONEs:
            if not consent(f"BACKUP {item}?"):
                continue
            copy(f"{HOME}/{item}", f"{cB}/{item}")
            ping(item)

        if item == "movies":
            movsPath = f"{HOME}/movies"
            if os.path.isdir(movsPath):
                movs = os.listdir(movsPath)
                with open("movies.txt", "w", encoding="utf-8") as M:
                    for mov in movs:
                        M.write(f"{mov}\n")
                shutil.move("movies.txt", cB)
                ping("movies.txt")


if __name__ == "__main__":
    main()
