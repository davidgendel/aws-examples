from __future__ import print_function

import json
import boto3

def lambda_handler(event, context):
    session = boto3.Session()
    
    # Create sessions
    cloudformation = session.client('cloudformation')
    
    response = cloudformation.delete_stack(
        StackName='serverless-wordpress',
    )