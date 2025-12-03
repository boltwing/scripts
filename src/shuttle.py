#!/usr/bin/env python3

"""
Shuttle is just the name of my digital journal!
"""

import subprocess
from datetime import datetime
from pathlib import Path

now = datetime.now()

year = now.strftime("%-y")
mon = now.strftime("%-b").lower()
date = now.strftime("%-d")

path = Path.home() / "notes" / "shuttle" / year / mon
path.mkdir(parents=True, exist_ok=True)

editor = "nvim"
today = path / f"{date}.md"

subprocess.run([editor, str(today)], check=False)
