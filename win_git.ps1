#!powershell

# GNU General Public License v3.0+ (see COPYING or https://www.gnu.org/licenses/gpl-3.0.txt)

# Anatoliy Ivashina <tivrobo@gmail.com>
# Pablo Estigarribia <pablodav@gmail.com>
# Michael Hay <project.hay@gmail.com>

#Requires -Module Ansible.ModuleUtils.Legacy.psm1

$params = Parse-Args -arguments $args -supports_check_mode $true
$check_mode = Get-AnsibleParam -obj $params -name "_ansible_check_mode" -default $false

# Module Params
$repo = Get-AnsibleParam -obj $params -name "repo" -failifempty $true -aliases "name"
$dest = Get-AnsibleParam -obj $params -name "dest"
$branch = Get-AnsibleParam -obj $params -name "branch" -default "master"
$clone = ConvertTo-Bool (Get-AnsibleParam -obj $params -name "clone" -default $true)
$update = ConvertTo-Bool (Get-AnsibleParam -obj $params -name "update" -default $false)
$recursive = ConvertTo-Bool (Get-AnsibleParam -obj $params -name "recursive" -default $true)
$replace_dest = ConvertTo-Bool (Get-AnsibleParam -obj $params -name "replace_dest" -default $false)
$accept_hostkey = ConvertTo-Bool (Get-AnsibleParam -obj $params -name "accept_hostkey" -default $false)

$result = New-Object psobject @{
    win_git = New-Object psobject @{
        repo           = $null
        dest           = $null
        clone          = $false
        replace_dest   = $true
        accept_hostkey = $true
        update         = $false
        recursive      = $true
        branch         = "master"
    }
    changed = $false
    cmd_msg = $null
}

# Add Git to PATH variable
# Test with git 2.14
$env:Path += ";" + "C:\Program Files\Git\bin"
$env:Path += ";" + "C:\Program Files\Git\usr\bin"
$env:Path += ";" + "C:\Program Files (x86)\Git\bin"
$env:Path += ";" + "C:\Program Files (x86)\Git\usr\bin"

# Functions
function Find-Command {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)] [string] $command
    )
    $installed = get-command $command -erroraction Ignore
    write-verbose "$installed"
    if ($installed) {
        return $installed
    }
    return $null
}

function FindGit {
    [CmdletBinding()]
    param()
    $p = Find-Command "git.exe"
    if ($p -ne $null) {
        return $p
    }
    $a = Find-Command "C:\Program Files\Git\bin\git.exe"
    if ($a -ne $null) {
        return $a
    }
    Fail-Json -obj $result -message "git.exe is not installed. It must be installed (use chocolatey)"
}

# Remove dest if it exests
function PrepareDestination {
    [CmdletBinding()]
    param()
    if ((Test-Path $dest) -And (-Not $check_mode)) {
        try {
            Remove-Item $dest -Force -Recurse | Out-Null
            Set-Attr $result "cmd_msg" "Successfully removed dir $dest."
            Set-Attr $result "changed" $true
        }
        catch {
            $ErrorMessage = $_.Exception.Message
            Fail-Json $result "Error removing $dest! Msg: $ErrorMessage"
        }
    }
}

# SSH Keys
function CheckSshKnownHosts {
    [CmdletBinding()]
    param()
    # Get the Git Hostrepo
    $gitServer = $($repo -replace "^(\w+)\@([\w-_\.]+)\:(.*)$", '$2')
    & cmd /c ssh-keygen.exe -F $gitServer | Out-Null
    $rc = $LASTEXITCODE

    if ($rc -ne 0) {
        # Host is unknown
        if ($accept_hostkey) {
            # workaroung for disable BOM
            # https://github.com/tivrobo/ansible-win_git/issues/7
            $sshHostKey = & cmd /c ssh-keyscan.exe -t ecdsa-sha2-nistp256 $gitServer
            $sshHostKey += "`n"
            $sshKnownHostsPath = Join-Path -Path $env:Userprofile -ChildPath \.ssh\known_hosts
            [System.IO.File]::AppendAllText($sshKnownHostsPath, $sshHostKey, $(New-Object System.Text.UTF8Encoding $False))
        }
        else {
            Fail-Json -obj $result -message  "Host is not known!"
        }
    }
}

function CheckSshIdentity {
    [CmdletBinding()]
    param()

    & cmd /c git.exe ls-remote $repo | Out-Null
    $rc = $LASTEXITCODE
    if ($rc -ne 0) {
        Fail-Json -obj $result -message  "Something wrong with connection!"
    }
}

function get_version {
    # samples the version of the git repo
    # example:  git rev-parse HEAD
    #           output: 931ec5d25bff48052afae405d600964efd5fd3da
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false, Position = 0)] [string] $refs = "HEAD"
    )
    $git_opts = @()
    $git_opts += "--no-pager"
    $git_opts += "rev-parse"
    $git_opts += "$refs"
    $git_cmd_output = ""

    [hashtable]$Return = @{}
    Set-Location $dest; &git $git_opts | Tee-Object -Variable git_cmd_output | Out-Null
    $Return.rc = $LASTEXITCODE
    $Return.git_output = $git_cmd_output

    return $Return
}

function checkout {
    [CmdletBinding()]
    param()
    [hashtable]$Return = @{}
    $local_git_output = ""

    $git_opts = @()
    $git_opts += "--no-pager"
    $git_opts += "checkout"
    $git_opts += "$branch"
    Set-Location $dest; &git $git_opts | Tee-Object -Variable local_git_output | Out-Null

    $Return.git_output = $local_git_output
    Set-Location $dest; &git status --short --branch | Tee-Object -Variable branch_status | Out-Null
    $branch_status = $branch_status.split("/")[1]
    Set-Attr $result.win_git "branch_status" "$branch_status"

    if ( $branch_status -ne "$branch" ) {
        Fail-Json $result "Failed to checkout to $branch"
    }

    return $Return
}

function clone {
    # git clone command
    [CmdletBinding()]
    param()

    Set-Attr $result.win_git "method" "clone"
    [hashtable]$Return = @{}
    $local_git_output = ""

    $git_opts = @()
    $git_opts += "--no-pager"
    $git_opts += "clone"
    $git_opts += $repo
    $git_opts += $dest
    $git_opts += "--branch"
    $git_opts += $branch
    if ($recursive) {
        $git_opts += "--recursive"
    }

    Set-Attr $result.win_git "git_opts" "$git_opts"

    #Only clone if $dest does not exist and not in check mode
    if ( (-Not (Test-Path -Path $dest)) -And (-Not $check_mode)) {
        &git $git_opts | Tee-Object -Variable local_git_output | Out-Null
        $Return.rc = $LASTEXITCODE
        $Return.git_output = $local_git_output
        Set-Attr $result "cmd_msg" "Successfully cloned $repo into $dest."
        Set-Attr $result "changed" $true
        Set-Attr $result.win_git "return_code" $LASTEXITCODE
        Set-Attr $result.win_git "git_output" $local_git_output
    }
    else {
        $Return.rc = 0
        $Return.git_output = $local_git_output
        Set-Attr $result "cmd_msg" "Skipping Clone of $repo becuase $dest already exists"
    }

    # Check if branch is the correct one
    Set-Location $dest; &git status --short --branch | Tee-Object -Variable branch_status | Out-Null
    $branch_status = $branch_status.split("/")[1]
    Set-Attr $result.win_git "branch_status" "$branch_status"

    if ( $branch_status -ne "$branch" ) {
        Fail-Json $result "Branch $branch_status is not $branch"
    }

    return $Return
}

function update {
    # git clone command
    [CmdletBinding()]
    param()

    Set-Attr $result.win_git "method" "pull"
    [hashtable]$Return = @{}
    $git_output = ""

    # Build Arguments
    $git_opts = @()
    $git_opts += "--no-pager"
    $git_opts += "pull"
    $git_opts += "origin"
    $git_opts += "$branch"

    Set-Attr $result.win_git "git_opts" "$git_opts"
    #Only update if $dest does exist and not in check mode
    if ((Test-Path -Path $dest) -and (-Not $check_mode)) {
        # move into correct branch before pull
        checkout
        # perform git pull
        Set-Location $dest; &git $git_opts | Tee-Object -Variable git_output | Out-Null
        $Return.rc = $LASTEXITCODE
        $Return.git_output = $git_output
        Set-Attr $result "cmd_msg" "Successfully updated $repo to $branch."
        #TODO: handle correct status change when using update
        Set-Attr $result "changed" $true
        Set-Attr $result.win_git "return_code" $LASTEXITCODE
        Set-Attr $result.win_git "git_output" $git_output
    }
    else {
        $Return.rc = 0
        $Return.git_output = $local_git_output
        Set-Attr $result "cmd_msg" "Skipping update of $repo"
    }

    return $Return
}


if ($repo -eq ($null -or "")) {
    Fail-Json $result "Repository cannot be empty or `$null"
}
Set-Attr $result.win_git "repo" $repo
Set-Attr $result.win_git "dest" $dest

Set-Attr $result.win_git "replace_dest" $replace_dest
Set-Attr $result.win_git "accept_hostkey" $accept_hostkey
Set-Attr $result.win_git "update" $update
Set-Attr $result.win_git "branch" $branch


$git_output = ""
$rc = 0

try {

    FindGit

    if ($replace_dest) {
        PrepareDestination
    }
    if ([system.uri]::IsWellFormedUriString($repo, [System.UriKind]::Absolute)) {
        # http/https repositories doesn't need Ssh handle
        # fix to avoid wrong usage of CheckSshKnownHosts CheckSshIdentity for http/https
        Set-Attr $result.win_git "valid_url" "$repo is valid url"
    }
    else {
        CheckSshKnownHosts
        CheckSshIdentity
    }
    if ($clone) {
        clone
    }
    if ($update) {
        update
    }
}
catch {
    $ErrorMessage = $_.Exception.Message
    Fail-Json $result "Error cloning $repo to $dest! Msg: $ErrorMessage - $git_output"
}

Set-Attr $result.win_git "msg" $cmd_msg
Set-Attr $result.win_git "changed" $changed

Exit-Json $result
