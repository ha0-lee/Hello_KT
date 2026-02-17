# ec2.start_instances 명령
# 이 코드는 람다가 실행될 때 EC2를 깨우는 역할을 합니다.

import boto3
import os

def lambda_handler(event, context):
    region = 'ap-northeast-2'
    
    # 테라폼이 넘겨준 "i-xxx,i-yyy" 문자열을 ['i-xxx', 'i-yyy'] 리스트로 변환
    raw_ids = os.environ.get('INSTANCE_IDS', '')
    if not raw_ids:
        print("제어할 인스턴스 ID가 없습니다.")
        return

    instance_ids = raw_ids.split(',')
    
    ec2 = boto3.client('ec2', region_name=region)
    ec2.start_instances(InstanceIds=instance_ids)
    
    print(f"다음 인스턴스들을 시작했습니다: {instance_ids}")