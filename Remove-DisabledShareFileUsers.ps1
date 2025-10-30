<#
.SYNOPSIS
    Finds and removes disabled ShareFile users, transferring their items and groups to an admin user.

.DESCRIPTION
    This script identifies disabled ShareFile users (both employees and clients) and removes them completely,
    reassigning their items and group memberships to a specified admin user. The script uses the ShareFile
    PowerShell snapin to interact with the ShareFile API.

.PARAMETER AdminUserId
    The user ID of the admin user who will receive the reassigned items and groups from deleted users.
    This parameter is mandatory.

.PARAMETER ClientConfigPath
    The path to the ShareFile client configuration file. Defaults to "c:\tmp\sfclient.sfps".

.PARAMETER TempDirectory
    The directory where temporary CSV files will be stored. Defaults to "C:\tmp\".

.PARAMETER WhatIf
    Shows what would be deleted without actually performing the deletion.

.EXAMPLE
    Remove-DisabledShareFileUsers -AdminUserId "admin@company.com"
    
    Finds and removes all disabled users, transferring items to admin@company.com

.EXAMPLE
    Remove-DisabledShareFileUsers -AdminUserId "admin123" -ClientConfigPath "d:\config\sf.sfps" -WhatIf
    
    Shows what would be deleted without actually performing the operation

.NOTES
    Requires the ShareFile PowerShell snapin to be installed and available.
    The script will create temporary CSV files in the specified temp directory.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$AdminUserId,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ClientConfigPath = "c:\tmp\sfclient.sfps",

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$TempDirectory = "C:\tmp\"
)

# Add ShareFile PowerShell snapin
Add-PSSnapin ShareFile

function Find-DisabledShareFileUsers {
    <#
    .SYNOPSIS
        Finds disabled ShareFile users of a specified type and exports them to CSV.
    
    .PARAMETER UserType
        The type of users to find (employee or client).
    
    .PARAMETER Client
        The ShareFile client object for API calls.
    
    .PARAMETER OutputPath
        The path where the CSV file will be saved.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('employee', 'client')]
        [string]$UserType,

        [Parameter(Mandatory)]
        [object]$Client,

        [Parameter(Mandatory)]
        [string]$OutputPath
    )

    begin {
        Write-Verbose "Starting search for disabled $UserType users"
        
        $entity = switch ($UserType.ToLower()) {
            'employee' { 'Accounts/Employees' }
            'client' { 'Accounts/Clients' }
        }
    }

    process {
        try {
            # Pull all users of the specified type
            Write-Verbose "Retrieving all $UserType users from ShareFile"
            $sfUsers = Send-SfRequest -Client $Client -Entity $entity

            $disabledUsers = @()
            $userCount = 0

            # Loop through each user to check disabled status
            foreach ($sfUserId in $sfUsers) {
                $userCount++
                Write-Progress -Activity "Checking $UserType users" -Status "Processing user $userCount of $($sfUsers.Count)" -PercentComplete (($userCount / $sfUsers.Count) * 100)
                
                # Get full user information including security settings
                $sfUser = Send-SfRequest -Client $Client -Entity Users -Id $sfUserId.Id -Expand Security
                
                # Check if user is disabled
                if ($sfUser.Security.IsDisabled -eq $true) {
                    Write-Verbose "Found disabled user: $($sfUser.Email)"
                    
                    $disabledUsers += [PSCustomObject]@{
                        UserId   = $sfUserId.Id
                        FullName = $sfUser.FullName
                        Email    = $sfUser.Email
                        UserType = $UserType
                    }
                }
            }

            Write-Progress -Activity "Checking $UserType users" -Completed
            
            # Export to CSV
            if ($disabledUsers.Count -gt 0) {
                $disabledUsers | Export-Csv -Path $OutputPath -Force -NoTypeInformation
                Write-Verbose "Exported $($disabledUsers.Count) disabled $UserType users to $OutputPath"
            } else {
                Write-Verbose "No disabled $UserType users found"
            }

            return $disabledUsers
        } catch {
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                'FindDisabledUsersFailed',
                [System.Management.Automation.ErrorCategory]::NotSpecified,
                $UserType
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }
    }
}

function Remove-DisabledShareFileUsersFromCsv {
    <#
    .SYNOPSIS
        Removes disabled ShareFile users listed in a CSV file.
    
    .PARAMETER CsvPath
        Path to the CSV file containing user information.
    
    .PARAMETER Client
        The ShareFile client object for API calls.
    
    .PARAMETER AdminUserId
        The admin user ID to reassign items and groups to.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [string]$CsvPath,

        [Parameter(Mandatory)]
        [object]$Client,

        [Parameter(Mandatory)]
        [string]$AdminUserId
    )

    begin {
        Write-Verbose "Starting removal of users from $CsvPath"
    }

    process {
        if (-not (Test-Path -Path $CsvPath)) {
            Write-Warning "CSV file not found: $CsvPath"
            return
        }

        try {
            $usersToDelete = Import-Csv -Path $CsvPath
            
            if ($usersToDelete.Count -eq 0) {
                Write-Verbose "No users found in CSV file: $CsvPath"
                return
            }

            $userCount = 0
            foreach ($user in $usersToDelete) {
                $userCount++
                Write-Progress -Activity "Deleting disabled users" -Status "Processing $($user.FullName) ($($user.Email))" -PercentComplete (($userCount / $usersToDelete.Count) * 100)
                
                $shouldProcessMessage = "Delete user '$($user.FullName)' ($($user.Email)) and reassign items to admin user '$AdminUserId'"
                
                if ($PSCmdlet.ShouldProcess($user.Email, $shouldProcessMessage)) {
                    try {
                        Write-Verbose "Deleting user: $($user.FullName) (ID: $($user.UserId))"
                        
                        Send-SfRequest -Client $Client -Method Delete -Entity Users -Id $user.UserId -Parameters @{
                            "completely" = "true"
                            "itemsReassignTo" = $AdminUserId
                            "groupsReassignTo" = $AdminUserId
                        }
                        
                        Write-Warning "Deleted user: $($user.FullName) ($($user.Email))"
                    } catch {
                        Write-Error "Failed to delete user '$($user.FullName)': $($_.Exception.Message)"
                    }
                }
            }

            Write-Progress -Activity "Deleting disabled users" -Completed
        } catch {
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $_.Exception,
                'RemoveUsersFailed',
                [System.Management.Automation.ErrorCategory]::NotSpecified,
                $CsvPath
            )
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }
    }
}

# Main script execution
try {
    Write-Verbose "Starting disabled ShareFile user removal process"
    Write-Verbose "Admin User ID: $AdminUserId"
    Write-Verbose "Client Config Path: $ClientConfigPath"
    Write-Verbose "Temp Directory: $TempDirectory"

    # Ensure temp directory exists
    if (-not (Test-Path -Path $TempDirectory)) {
        Write-Verbose "Creating temp directory: $TempDirectory"
        New-Item -Path $TempDirectory -ItemType Directory -Force | Out-Null
    }

    # Initialize ShareFile client
    Write-Verbose "Initializing ShareFile client"
    if (-not (Test-Path -Path $ClientConfigPath)) {
        Write-Verbose "Creating new ShareFile client configuration"
        $client = New-SfClient -Name $ClientConfigPath
    } else {
        Write-Verbose "Using existing ShareFile client configuration"
        $client = Get-SfClient -Name $ClientConfigPath
    }

    # Validate and resolve AdminUserId to actual ShareFile user ID
    Write-Verbose "Validating and resolving admin user ID: $AdminUserId"
    $resolvedAdminUserId = $null
    
    # Check both employee and client entities for the admin user
    $adminUserTypes = @('Accounts/Employees', 'Accounts/Clients')
    
    foreach ($adminEntity in $adminUserTypes) {
        Write-Verbose "Searching for admin user in $adminEntity"
        $adminUsers = Send-SfRequest -Client $client -Entity $adminEntity
        
        foreach ($adminUser in $adminUsers) {
            # Get full user details to check email and other properties
            $fullAdminUser = Send-SfRequest -Client $client -Entity Users -Id $adminUser.Id
            
            # Match by ID or email
            if ($fullAdminUser.Id -eq $AdminUserId -or $fullAdminUser.Email -eq $AdminUserId) {
                $resolvedAdminUserId = $fullAdminUser.Id
                Write-Verbose "Found admin user: $($fullAdminUser.FullName) ($($fullAdminUser.Email)) with ID: $resolvedAdminUserId"
                break
            }
        }
        
        if ($resolvedAdminUserId) {
            break
        }
    }
    
    # Validate that admin user was found
    if (-not $resolvedAdminUserId) {
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new("Admin user '$AdminUserId' not found in ShareFile. Please verify the user ID or email address."),
            'AdminUserNotFound',
            [System.Management.Automation.ErrorCategory]::ObjectNotFound,
            $AdminUserId
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }
    
    Write-Host "Using admin user ID: $resolvedAdminUserId" -ForegroundColor Green

    # Find disabled users for both employee and client types
    $allDisabledUsers = @()
    $userTypes = @('employee', 'client')
    
    foreach ($userType in $userTypes) {
        $csvPath = Join-Path -Path $TempDirectory -ChildPath "$userType.csv"
        Write-Host "Searching for disabled $userType users..." -ForegroundColor Yellow
        
        $disabledUsers = Find-DisabledShareFileUsers -UserType $userType -Client $client -OutputPath $csvPath
        $allDisabledUsers += $disabledUsers
        
        Write-Host "Found $($disabledUsers.Count) disabled $userType users" -ForegroundColor Green
    }

    # Display summary
    Write-Host "`nSummary of disabled users found:" -ForegroundColor Cyan
    Write-Host "Total disabled users: $($allDisabledUsers.Count)" -ForegroundColor White
    
    if ($allDisabledUsers.Count -gt 0) {
        Write-Host "Users will be deleted and their items/groups transferred to: $resolvedAdminUserId" -ForegroundColor Yellow
        
        # Delete users from both CSV files
        foreach ($userType in $userTypes) {
            $csvPath = Join-Path -Path $TempDirectory -ChildPath "$userType.csv"
            if (Test-Path -Path $csvPath) {
                Write-Host "`nProcessing $userType users for deletion..." -ForegroundColor Yellow
                Remove-DisabledShareFileUsersFromCsv -CsvPath $csvPath -Client $client -AdminUserId $resolvedAdminUserId
            }
        }
        
        Write-Host "`nDisabled user removal process completed successfully!" -ForegroundColor Green
    } else {
        Write-Host "No disabled users found. No action required." -ForegroundColor Green
    }

} catch {
    Write-Error "Script execution failed: $($_.Exception.Message)"
    exit 1
} finally {
    Write-Verbose "Disabled ShareFile user removal process finished"
}