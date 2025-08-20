# fastapi app boiler plate:
import subprocess
import asyncio
import os
import uvicorn
import dotenv

from typing import List
from fastapi import FastAPI, HTTPException

dotenv.load_dotenv()  # Load environment variables from .env file

app = FastAPI()
sync_lock = asyncio.Lock()

g_drives: List[str] = []

RASPI_SUDO_PASSWORD = os.getenv("RASPI_SUDO_PASSWORD")
if not RASPI_SUDO_PASSWORD:
    raise ValueError("RASPI_SUDO_PASSWORD environment variable is not set")
MOUNT_DIRECTORY = "/media/nas_drives"

@app.get("/")
async def read_root():
    return {"Hello": "World"}

@app.get("/sync")
async def sync(dry_run: bool):
    if sync_lock.locked():
        print("Sync already in progress")
        raise HTTPException(status_code=429, detail="Sync already in progress")
    if not g_drives or len(g_drives) < 2:
        raise HTTPException(status_code=404, detail="less than 2 mounted drives found")
    async with sync_lock:
        # Place sync logic here
        primary_drive = g_drives[0]
        # slice rest of the drives
        for drive in g_drives[1:]:
            print(f"Syncing from {primary_drive} to {drive}")
            await execute_single_sync_async(primary_drive, drive, RASPI_SUDO_PASSWORD, dry_run=dry_run)
        return {"status": "ok", "result": "Sync completed"}

async def execute_single_sync_async(copy_from: str, copy_to: str, sudo_password: str, dry_run: bool=True) -> str:
    return await asyncio.to_thread(execute_single_sync, copy_from, copy_to, sudo_password, dry_run)

def execute_single_sync(copy_from: str, copy_to: str, sudo_password: str, dry_run: bool=True) -> str:

    cmd = [
        "sudo",
        "rsync",
        "-av",
        "--delete",
    ]
    if dry_run:
        cmd.append("--dry-run")
    cmd.extend([
        f"{MOUNT_DIRECTORY}/{copy_from}/",
        f"{MOUNT_DIRECTORY}/{copy_to}/"
    ])

    print(f"Executing command: {' '.join(cmd)}")

    result = subprocess.run(cmd, check=True, capture_output=True, text=True, input=sudo_password + "\n")
    return result.stdout

def load_mounted_drives(drives: List[str]) -> None:
    if drives:
        return
    with open("mounted_drives.txt", "r") as f:
        for line in f:
            drive = line.strip()
            if drive:
                drives.append(drive)
    return drives


async def main():
    load_mounted_drives(g_drives)
    if g_drives:
        for drive in g_drives:
            print(f"Found mounted drive: {drive}")
    else:
        print("No mounted drives found.")


if __name__ == "__main__":
    asyncio.run(main())
    uvicorn.run(app, host="0.0.0.0", port=8069)