# Must be placed in ~\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1
# Can also be placed C:\Program Files\PowerShell\7\profile.ps1 for Powershell 7
function Get-CmdletAlias ($cmdletname) {
  Get-Alias |
    Where-Object -FilterScript {$_.Definition -like "$cmdletname"} |
      Format-Table -Property Definition, Name -AutoSize
}



# Define findstr as grep
Set-Alias -Name grep -Value findstr

# Define ls as ll
Set-Alias -Name ll -Value ls

# Define vim as nvim
Set-Alias -Name vim -Value nvim

# Define g++ as clang++
Set-Alias -Name g++ -Value clang++

# Define gcc as clang
Set-Alias -Name gcc -Value clang

# Define ifconfig as ipconfig
Set-Alias -Name ifconfig -Value ipconfig

# Define pwsh as powershell
Set-Alias -Name pwsh -Value powershell

# Define ccat as pygmentize
function ccat ($filename) {
        pygmentize -g $filename
}


# Define touch to create a file
function touch ($name) {
        New-Item -Path $name -ItemType File

}

# Define which to file path for a command
function which ($command) {
    Get-Command -Name $command -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty Path -ErrorAction SilentlyContinue
}


# Remove the default powershell curl alias
if (Test-Path Alias:curl) {
	Remove-Item Alias:curl
}


# Remove the default powershell wget alias
if (Test-Path Alias:wget) {
	Remove-Item Alias:wget
}
