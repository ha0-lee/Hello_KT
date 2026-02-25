# ec2.start_instances 명령
# 이 코드는 람다가 실행될 때 EC2를 깨우는 역할을 합니다.

import boto3
import os
import json

def lambda_handler(event, context):
    """
    EC2 인스턴스들을 시작하는 Lambda 핸들러
    """
    region = 'ap-northeast-2'
    
    # 환경변수에서 인스턴스 ID 가져오기 (안전한 방식)
    raw_ids = os.environ.get('INSTANCE_IDS', '')
    
    if not raw_ids:
        error_msg = "❌ INSTANCE_IDS 환경변수가 설정되지 않았습니다."
        print(error_msg)
        return {
            'statusCode': 400,
            'body': json.dumps({'error': error_msg})
        }
    
    # 쉼표로 구분된 문자열을 리스트로 변환하고 공백 제거
    instance_ids = [id.strip() for id in raw_ids.split(',') if id.strip()]
    
    if not instance_ids:
        error_msg = "❌ 유효한 인스턴스 ID가 없습니다."
        print(error_msg)
        return {
            'statusCode': 400,
            'body': json.dumps({'error': error_msg})
        }
    
    try:
        ec2 = boto3.client('ec2', region_name=region)
        
        # EC2 인스턴스 시작
        response = ec2.start_instances(InstanceIds=instance_ids)
        
        print(f"✅ 다음 인스턴스들을 시작했습니다: {instance_ids}")
        print(f"📊 응답: {response['StartingInstances']}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'EC2 인스턴스 시작 성공',
                'instances': instance_ids,
                'details': response['StartingInstances']
            }, default=str)
        }
        
    except Exception as e:
        error_msg = f"❌ EC2 시작 중 오류 발생: {str(e)}"
        print(error_msg)
        return {
            'statusCode': 500,
            'body': json.dumps({'error': error_msg})
        }