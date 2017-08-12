#!powershell
# 
# 
# Anatoliy Ivashina <tivrobo@gmail.com>
#
# collaborators:
# Pablo Estigarribia <pablodav@gmail.com>
# 
# 

# WANT_JSON
# POWERSHELL_COMMON

$params = Parse-Args $args;

$result = New-Object psobject @{
    win_git = New-Object psobject @{
        name              = $null
        dest              = $null
        replace_dest      = $false
        accept_hostkey    = $false
        update            = $false
        branch            = "master"
    }
    changed = $false
}

$name = Get-AnsibleParam -obj $params -name "name" -failifempty $true
$dest = Get-AnsibleParam -obj $params -name "dest"
$update = Get-AnsibleParam -obj $params -name "update" -default $false
$branch = Get-AnsibleParam -obj $params -name "branch" -default "master"
$replace_dest = ConvertTo-Bool (Get-AnsibleParam -obj $params -name "replace_dest" -default $false)
$accept_hostkey = ConvertTo-Bool (Get-AnsibleParam -obj $params -name "accept_hostkey" -default $false)

$_ansible_check_mode = Get-AnsibleParam -obj $params -name "_ansible_check_mode" -default $false

# Add Git to PATH variable
# Test with git 2.14
$env:Path += ";" + "C:\Program Files\Git\bin"
$env:Path += ";" + "C:\Program Files\Git\usr\bin"
$env:Path += ";" + "C:\Program Files (x86)\Git\bin"
$env:Path += ";" + "C:\Program Files (x86)\Git\usr\bin"

# Functions
Function Find-Command
{
    [CmdletBinding()]
    param(
      [Parameter(Mandatory=$true, Position=0)] [string] $command
    )
    $installed = get-command $command -erroraction Ignore
    write-verbose "$installed"
    if ($installed)
    {
        return $installed
    }
    return $null
}

Function FindGit
{
    [CmdletBinding()]
    param()
    $p = Find-Command "git.exe"
    if ($p -ne $null)
    {
        return $p
    }
    $a = Find-Command "C:\Program Files\Git\bin\git.exe"
    if ($a -ne $null)
    {
        return $a
    }
    Fail-Json -obj $result -message "git.exe is not installed. It must be installed (use chocolatey)"
}

# Check destination folder, create if not exist
function PrepareDestination
{
    [CmdletBinding()]
    param()
    if (Test-Path $dest) {
        $directoryInfo = Get-ChildItem $dest -Force | Measure-Object
        if ($directoryInfo.Count -ne 0) {
            if ($replace_dest) {
                # Clean destination
                Remove-Item $dest -Force -Recurse | Out-Null
            }
            else {
                Throw "Destination folder not empty!"
            }
        }
    }
    else {
        # Create destination folder
        New-Item $dest -ItemType Directory -Force | Out-Null
    }
}

# SSH Keys
function CheckSshKnownHosts
{
    [CmdletBinding()]
    param()
    # Get the Git Hostname
    $gitServer = $($name -replace "^(\w+)\@([\w-_\.]+)\:(.*)$", '$2')
    & cmd /c ssh-keygen.exe -F $gitServer | Out-Null
    $rc = $LASTEXITCODE
    
    if ($rc -ne 0)
    {
        # Host is unknown
        if ($accept_hostkey)
        {
            & cmd /c ssh-keyscan.exe -t ecdsa-sha2-nistp256 $gitServer | Out-File -Append "$env:Userprofile\.ssh\known_hosts"
        }
        else
        {
            Fail-Json -obj $result -message  "Host is not known!"
        }
    }
}

function CheckSshIdentity
{
    [CmdletBinding()]
    param()

    & cmd /c git.exe ls-remote $name | Out-Null
    $rc = $LASTEXITCODE
    if ($rc -ne 0) {
        Fail-Json -obj $result -message  "Something wrong with connection!"
    }
}
function clone
{
    # git clone command
    [CmdletBinding()]
    param()

    Set-Attr $result.win_git "method" "clone"
    [hashtable]$Return = @{} 
    $git_output = ""

    $git_opts = @()
    $git_opts += "clone"
    $git_opts += $name
    $git_opts += $dest

    Set-Attr $result.win_git "git_opts" "$git_opts"

    &git $git_opts | Tee-Object -Variable git_output | Out-Null
    $Return.rc = $LASTEXITCODE
    $Return.git_output = $git_output

    return $Return
    
}

function update
{
    # git clone command
    [CmdletBinding()]
    param()

    Set-Attr $result.win_git "method" "pull"
    [hashtable]$Return = @{} 
    $git_output = ""

    # Build Arguments
    $git_opts = @()
    $git_opts += "pull"
    $git_opts += "origin"
    $git_opts += "$branch"

    Set-Attr $result.win_git "git_opts" "$git_opts"

    Set-Location $dest; &git $git_opts | Tee-Object -Variable git_output | Out-Null
    $Return.rc = $LASTEXITCODE
    $Return.git_output = $git_output

    # TODO: 
    # handle correct CHANGED for updated repository

    return $Return
    
}



if ($name -eq ($null -or "")) {
    Fail-Json $result "Repository cannot be empty or `$null"
}
Set-Attr $result.win_git "name" $name
Set-Attr $result.win_git "dest" $dest

Set-Attr $result.win_git "replace_dest" $replace_dest
Set-Attr $result.win_git "accept_hostkey" $accept_hostkey
Set-Attr $result.win_git "update" $update
Set-Attr $result.win_git "branch" $branch


$git_output = ""
$rc = 0

If ($_ansible_check_mode -eq $true) {
    $git_output = "Would have copied the contents of $name to $dest"
    $rc = 0
}
Else {
    Try {

        FindGit

        if (Test-Path $dest) {
        } else {
            PrepareDestination
        }

        if ($replace_dest) {
            PrepareDestination
        }

        if ([system.uri]::IsWellFormedUriString($name,[System.UriKind]::Absolute)) {
            # http/https repositories doesn't need Ssh handle
            # fix to avoid wrong usage of CheckSshKnownHosts CheckSshIdentity for http/https
            Set-Attr $result.win_git "valid_url" "$name is valid url"
        } else {
            CheckSshKnownHosts
            CheckSshIdentity
        }

        if (-not $update) {
            $Return = clone
            $rc = $Return.rc
            $git_output = $Return.git_output
        }

        if ($update) {
            $Return = update
            $rc = $Return.rc
            $git_output = $Return.git_output
        }
        
    }
    Catch {
        $ErrorMessage = $_.Exception.Message
        Fail-Json $result "Error cloning $name to $dest! Msg: $ErrorMessage - $git_output"
    }
}

Set-Attr $result.win_git "return_code" $rc
Set-Attr $result.win_git "output" $git_output

# TODO: 
# handle correct CHANGED for updated repository
$cmd_msg = "Success"
If ($rc -eq 0) {
    $cmd_msg = "Successfully cloned $name into $dest."
    $changed = $true
}
Else {
    $error_msg = SearchForError $git_output "Fatal Error!"
    Fail-Json $result $error_msg
}

Set-Attr $result.win_git "msg" $cmd_msg
Set-Attr $result.win_git "changed" $changed

Exit-Json $result
