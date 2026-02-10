# ec2.stop_instances 명령
# 이 코드는 람다가 실행될 때 EC2를 정지시키는 역할을 합니다.

import boto3
import os

def lambda_handler(event, context):
    region = 'ap-northeast-2'
    instance_ids = os.environ['INSTANCE_IDS'].split(',')
    
    ec2 = boto3.client('ec2', region_name=region)
    
    # EC2 중지 명령
    ec2.stop_instances(InstanceIds=instance_ids)
    print(f'성공적으로 EC2를 중지했습니다: {instance_ids}')