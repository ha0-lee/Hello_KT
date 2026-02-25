fastapi 실행 명령어

uvicorn main:app --reload

상세 가이드: 항상 Destroy 후 Apply 할 때의 루틴
[Step 1] 인프라 삭제 (S3와 락 테이블은 보존)
파일 주석: dynamodb.tf, variables.tf, backend.tf를 제외한 모든 .tf 파일의 내용을 /* ... */로 감싸 주석 처리합니다.

실행: terraform apply

S3 백엔드가 살아있는 상태이므로 별도의 옵션 없이 바로 실행됩니다.

서버, 네트워크, 람다 등이 모두 삭제됩니다.
+2

[Step 2] 인프라 다시 생성
파일 주석 해제: 모든 파일의 주석(/*, */)을 제거하여 원래 코드로 복구합니다.

실행: terraform apply

이미 S3에 tfstate가 연결되어 있으므로, 테라폼은 현재 인프라가 없음을 확인하고 새로 싹 생성합니다.


PEM 키 권한 복구: provider.tf에서 새로운 키가 생성될 수 있으므로, 다시 권한 설정을 수행합니다.

icacls .\Hello_kt.pem /inheritance:r
icacls .\Hello_kt.pem /grant:r "${env:USERNAME}:R"
