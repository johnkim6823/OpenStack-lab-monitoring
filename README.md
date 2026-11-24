# OpenStack-lab-monitoring

VirtualBox 5노드 OpenStack 2024.1(Caracal) + Ceph 19.2 실습 환경의 모니터링 스택 설정 저장소.

## 구성

| 구성 요소 | 역할 |
| --- | --- |
| Prometheus | 지표 수집(대상 20개), 알림 규칙 11개 평가 |
| blackbox_exporter | OpenStack API 7개 HTTP 확인, DB와 MQ 등 3개 TCP 확인 |
| Alertmanager | 알림 그룹화(alertname, node), critical이 있으면 warning 억제 |
| Loki | 5개 노드 Alloy가 보내는 journal과 OpenStack 로그 저장(7일) |
| Grafana | 데이터 소스와 대시보드를 provisioning 파일로 관리 |

## 디렉터리

```text
docker-compose.yml
prometheus/prometheus.yml, prometheus/rules/lab.yml
blackbox/blackbox.yml
loki/loki.yml
alertmanager/alertmanager.yml
grafana/provisioning/, grafana/dashboards/
```

## 실행

```bash
cp .env.example .env   # GRAFANA_ADMIN_PASSWORD 설정
docker compose up -d
```

## 배포 방식

이 저장소의 main 브랜치가 실제 설정의 기준이다. 서버에서 직접 수정하지 않고, 변경은 Jenkins 파이프라인(검증 → 사전 적용 → 배포 → 사후 확인 → 롤백)으로만 반영한다. (작성 중)
