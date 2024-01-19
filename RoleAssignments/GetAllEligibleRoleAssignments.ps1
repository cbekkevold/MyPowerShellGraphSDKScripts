Connect-MgGraph -Scopes AuditLog.Read.All, RoleEligibilitySchedule.Read.Directory, Directory.Read.All

$AllActivations = @()
$AllEligibleAssignments = @()
$RoleActivations = Get-MgBetaAuditLogDirectoryAudit -All -Filter "operationType eq 'ActivateRole' and category eq 'RoleManagement'"
$EligibleAssignments = Get-MgBetaRoleManagementDirectoryRoleEligibilityScheduleInstance -All

foreach ($RoleActivation in $RoleActivations) {
    if ($RoleActivation.Result -eq "success") {
        $tempObject = [pscustomobject]@{
            UserDisplayName   = $RoleActivation.InitiatedBy.User.DisplayName
            UserPrincipalName = $RoleActivation.InitiatedBy.User.UserPrincipalName
            Role              = $RoleActivation.TargetResources[0].DisplayName
            ActivationTime    = $RoleActivation.ActivityDateTime
        }
        $AllActivations += $tempObject
    }
}
$LatestActivations = $AllActivations | Group-Object  UserPrincipalName, Role | Foreach-Object { $_.Group | Sort-Object ActivationTime | Select-Object -Last 1 }

foreach ($Assignment in $EligibleAssignments) {
    $LastActivated = "N/A"
    $RoleName = $($RoleDefinitions | Where-Object { $_.Id -eq $assignment.RoleDefinitionId }).DisplayName
    $Object = Get-MgBetaDirectoryObject -DirectoryObjectId $assignment.PrincipalId -ErrorAction Ignore

    switch ($Object.AdditionalProperties.'@odata.type') {
        "#microsoft.graph.user" { $ObjectType = "User" }
        "#microsoft.graph.group" { $ObjectType = "Group" }
        "#microsoft.graph.servicePrincipal" { $ObjectType = "ServicePrincipal" }
        Default { $ObjectType = $Object.AdditionalProperties.'@odata.type' }
    }
    if ($ObjectType -eq "User") {
        $Activation = $LatestActivations | Where-Object { ($_.UserDisplayName -eq $Object.AdditionalProperties.displayName) -and ($_.Role -eq $RoleName) } | Select-Object ActivationTime
        if ($Activation) {
            $LastActivated = $Activation.ActivationTime
        }
        else {
            $LastActivated = "Not in 30 days"
        }
    }
    if (-not $assignment.EndDateTime) {
        $AssignmentType = "Eligible (Permanent)"
    }
    else {
        $AssignmentType = "Eligible"
    }    
    $tempObject = [pscustomobject]@{
        RoleName       = $RoleName
        PrincipalName  = $Object.AdditionalProperties.displayName
        PrincipalType  = $ObjectType
        AssignmentType = $AssignmentType
        StartDate      = $assignment.StartDateTime
        EndDate        = $assignment.EndDateTime
        LastActivated  = $LastActivated
    }
    $AllEligibleAssignments += $tempObject
}

$AllEligibleAssignments | Export-Excel -AutoSize -TableName "RoleAssignments" -ClearSheet