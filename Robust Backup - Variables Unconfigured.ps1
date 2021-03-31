########################################################################################################################
# This script is intended to be set to run 1x/day in Task Scheduler at a specified time. The action of it as follows:
#
# Determine the day of the week. Then ->
# If the day of the week matches a day specified ($runOndays) by the instantiator of the script (you), it runs a robocopy backup. If not, the script exits with no action.
# Backups will be placed in a subdirectory of the specified destination directory ($backupToFolder) titled the day of the week the backup was run.
# Transcripts of the robocopy process are written to another subdirectory called "PowerShell Transcripts" within that day of the week backup destination folder.
# Before running the robocopy, all current files in the destination directory are renamed to *.backup, preventing data loss due to interruption of the robocopy process.
# Then the robocopy proceeds.
# If the robocopy succeeds, all former backup files just named *.backup will be removed. If the robocopy fails, they will be left in place.
#
# You only need to edit variable values in this section of the script to change ->
# 1) the location of the source ($backupFromFolder) and destination ($backupToFolder) of data backups - use the entire path in double quotes (") and leave off the trailing slash (\)
# 2) which days of the week the backup runs on ($runOnDays), where 0=Sunday, 1=Monday, 2=Tuesday, 3=Wednesday, 4=Thursday, 5=Friday, and 6=Saturday, separated by commas
# 3) if the backup will be written to a separate folder for the day of the week it was backed up on (i.e. backups that run on Mondays will be placed in a subfolder of the $backupToFolder called "Monday"), or instead if all backups will be written to the same location (top level of $backupToFolder) regardless of the day of the week
#         (choose $separateBackupPerDayOfWeek = "yes" or $separateBackupPerDayOfWeek = "no")
# 4) how many days historical PowerShell transcripts created by this script are kept before they are deleted ($keepTranscriptsAgeLimitInDays)

#leave off trailing slash (\)!
$backupFromFolder = "\\backup\from\here"
$backupToFolder = "D:\backup\to\here"

$runOnDays = 1,3,4,6 #monday, wednesday, thursday, saturday, for example

#must be "yes" or "no"
$separateBackupPerDayOfWeek = "yes"

$keepTranscriptsAgeLimitInDays = 365

########################################################################################################################
# Do not edit the lines below.

$ErrorActionPreference = "Continue"
$currentDayOfWeek = (Get-Date).DayOfWeek.value__
$currentDate = Get-Date -format "yyyyMMdd"

function RenameRobocopyRemove($day) { 

    # Switch here is to translate the output of (Get-Date).DayOfWeek.value__ to the english day of the week name to create the backup directory tree.
    switch ($day) {
        0 {$dayOfWeek = "Sunday"; Break}
        1 {$dayOfWeek = "Monday"; Break}
        2 {$dayOfWeek = "Tuesday"; Break}
        3 {$dayOfWeek = "Wednesday"; Break}
        4 {$dayOfWeek = "Thursday"; Break}
        5 {$dayOfWeek = "Friday"; Break}
        6 {$dayOfWeek = "Saturday"; Break}
        default { $dayOfWeek = "null" } #This is the 'catch-all' in the case of no match for PS switch statements.
    }

    if ($separateBackupPerDayOfWeek -eq "yes") {
        $placeholder = "\$dayOfWeek"
    } elseif ($separateBackupPerDayOfWeek -eq "no") {
        $placeholder = ""
    }

    Write-Host $dayOfWeek
    $testPath = Test-Path "$backupToFolder$placeholder\PowerShell Transcripts"
    Write-Host $testPath
    if ($testPath -eq $False) {
        New-Item -ItemType directory -Path "$backupToFolder$placeholder\PowerShell Transcripts"
    }
    Start-Transcript -path "$backupToFolder$placeholder\PowerShell Transcripts\powershell_transcript_backup_$currentDate.txt" -append
    Get-ChildItem -Path "$backupToFolder$placeholder" -Exclude *PowerShell* | Rename-Item -NewName {$_.Name + '.backup'} #This command will fail to rename the transcript to .backup because it's in the process of being written.

    robocopy $backupFromFolder "$backupToFolder$placeholder" /E /R:2 /W:5
    <#
    robocopy switches, i am using /E /R:2 /W:5:
    /S : Copy Subfolders.
    /E : Copy Subfolders, including Empty Subfolders.
    /R:n : Number of Retries on failed copies - default is 1 million.
    /W:n : Wait time between retries - default is 30 seconds.
    #>

    $robocopySuccessCodes = 0,1,3,5,6,7,11
    $robocopyFailureCodes = 2,8
    # See robocopy exit codes https://ss64.com/nt/robocopy-exit.html
        # I think typically robocopy exits with code 11 in this setup:
        # 1 - Files are copied successfully (backed up as intended)
        # 2 - Extra files are found (the .backup versions)
        # 8 - The OneDrive specific UUID file cannot be copied.
        # Sum of exit codes 1 + 2 + 8 = Exit code 11

    if ($robocopySuccessCodes -contains $lastexitcode) {

        Write-Host "Robocopy succeeded with exit code:" $lastexitcode
        #The below lines were added because Remove-Item cannot can't handle deleting items with over 260 characters in the path.
        #Robocopy however, can read and write files with other 260 characters in the path so I mirror over an empty directory, and then delete (Remove-Item).
        Write-Host "Mirroring blank folder and removing *.backup versions."
        $backupFolders = Get-ChildItem -Path "$backupToFolder$placeholder\*.backup"
        foreach ($item in $backupFolders) {
            robocopy "C:\UTIL\Board Backup Script\Empty" "$item" /MIR
        } 
        Remove-Item -Path "$backupToFolder$placeholder\*.backup" -Recurse -Force

    } elseif ($robocopyFailureCodes -contains $lastexitcode) {

        Write-Host "Robocopy failed with exit code:" $lastexitcode
        Write-Host "Leaving .backup versions intact."

    } else {

        Write-Host "Robocopy completed with exit code:" $lastexitcode
        Write-Host "Leaving .backup versions intact."

    }

    # Remove transcripts older than days specifed in $keepTranscriptsAgeLimitInDays
    Write-Host "Removing any transcripts older than $keepTranscriptsAgeLimitInDays days old."
    $dateToDelete = (Get-Date).addDays(-$keepTranscriptsAgeLimitInDays)
    Get-ChildItem -Path "$backupToFolder$placeholder\PowerShell Transcripts\" -Recurse -Force | Where-Object {  $_.LastWriteTime -lt $dateToDelete } | Remove-Item -Force

    Stop-Transcript

}

if ($runOnDays -contains $currentDayOfWeek) {

    RenameRobocopyRemove($currentDayOfWeek)

} else {

    exit

}

exit