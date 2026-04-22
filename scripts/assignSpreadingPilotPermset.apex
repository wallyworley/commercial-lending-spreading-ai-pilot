PermissionSet permissionSet = [
    SELECT Id
    FROM PermissionSet
    WHERE Name = 'Spreading_Pilot_Analyst'
    LIMIT 1
];

List<PermissionSetAssignment> existingAssignments = [
    SELECT Id
    FROM PermissionSetAssignment
    WHERE AssigneeId = :UserInfo.getUserId()
    AND PermissionSetId = :permissionSet.Id
    LIMIT 1
];

if (existingAssignments.isEmpty()) {
    insert new PermissionSetAssignment(
        AssigneeId = UserInfo.getUserId(),
        PermissionSetId = permissionSet.Id
    );
    System.debug('ASSIGNED_SPREADING_PILOT_ANALYST=true');
} else {
    System.debug('ASSIGNED_SPREADING_PILOT_ANALYST=already_assigned');
}
