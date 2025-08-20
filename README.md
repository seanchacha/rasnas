# rasnas

A weekend project to help me set up a simple raspberry pi 5 home network attached storage (NAS) solution with drive mirroring in a user-friendly way

<img src="rasnas.gif" alt="RasNas Demo GIF" width="550">

## Hardware
Successfully running on raspberry pi 5 (Raspberry Pi OS Bookworm 64-bit lite)  
Use external drives with usb-a connectivity

## Software
Here's what it uses (and automatically installs):
- [samba](https://www.samba.org/) - for LAN file sharing
- [gum](https://github.com/charmbracelet/gum) - for making shell script more interactive
- [uv](https://github.com/astral-sh/uv) - for python venv and version management
- You can also use [Tailscale](https://tailscale.com/) or a VPN of your choice to access your files from anywhere. [Install](https://tailscale.com/download/linux)

## Setup
Set up your raspberry pi with ssh access using the [Imager](https://www.raspberrypi.com/software/)

Once ssh'd into your pi,  
clone this repo (install git if needed)
```bash
git clone https://github.com/seanchacha/rasnas.git
```
enter the directory  
```bash
cd rasnas
```
and run the setup script  
```bash
bash ./setup.sh
```

The script will automatically install depedencies and show you a menu with the options:  
> set up drives             
  set up samba              
  start server              
  kill server               
  open server session       
  unmount drives            
  exit

Go through setting up the drives, then samba, then the server in this order
Your primary drive will be the one that the other drives copy from

## Usage
Once you start the server, you can enter in your browser (with VPN access):
```bash
<your-pi-ip-address>:8069/docs
```
and send a request to the /sync endpoint with dry-run set to False whenever you make a change to your primary drive and want to sync all the other drives to it 