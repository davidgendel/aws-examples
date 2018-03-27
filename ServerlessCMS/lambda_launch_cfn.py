from __future__ import print_function

import json
import boto3

def lambda_handler(event, context):
    session = boto3.Session()
    
    # Create sessions
    cloudformation = session.client('cloudformation')
    rds = session.client('rds')
    
    snapshots=[]
    
    # Print out bucket names
    for snapshot in rds.describe_db_snapshots(SnapshotType='manual', DBInstanceIdentifier='wordpress')['DBSnapshots']:
        if (snapshot['Status']=='available'):
            snapshots.append(snapshot)
            print(snapshot)
            print(snapshot['SnapshotCreateTime'])
            print(snapshot['DBSnapshotIdentifier'])
    
    #snapshots = rds.describe_db_snapshots(SnapshotType='manual', DBInstanceIdentifier='wordpress')['DBSnapshots']
    snapshots.sort(key=lambda d: d['SnapshotCreateTime'])
    latest_snapidentifier = snapshots[-1]['DBSnapshotIdentifier']
    print(latest_snapidentifier)
    
    response = cloudformation.create_stack(
        StackName='serverless-wordpress',
        TemplateURL='https://s3.amazonaws.com/<your bucket name>/cfn/serverless-wordpress.cform',
        Parameters=[
            {
                'ParameterKey': 'RDSSnapshot',
                'ParameterValue': latest_snapidentifier
            },
        ]
    )
    print response