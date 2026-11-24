#!/usr/bin/env bash
# monitor 배포 단계 스크립트. Jenkins가 ssh로 monitor에 보내 실행한다.
# 사용: pipeline.sh <prepare|validate|canary|deploy|verify|rollback|cleanup> [commit]
set -euo pipefail
CMD=${1:?단계 이름 필요}; SHA=${2:-}
REPO=https://github.com/johnkim6823/OpenStack-lab-monitoring.git
LIVE=$HOME/monitoring; STAGE=$HOME/staging; STATE=$HOME/.deploy-state
log(){ echo "[$(date -u +%T) UTC] $*"; }
img(){ grep -oE "$1:[^ \"']+" "$STAGE/docker-compose.yml" | head -n1; }

targets(){ curl -s -m 5 "$1/api/v1/targets" | python3 -c "import json,sys; t=json.load(sys.stdin)['data']['activeTargets']; print(sum(x['health']=='up' for x in t), len(t))" 2>/dev/null || echo "0 0"; }
rules(){ curl -s -m 5 "$1/api/v1/rules" | python3 -c "import json,sys; r=[x for g in json.load(sys.stdin)['data']['groups'] for x in g['rules']]; b=[x['name'] for x in r if x.get('health')=='err']; print(len(r), len(b), ','.join(b) or '-')" 2>/dev/null || echo "0 0 -"; }

apply_changes(){  # $1 = 바뀐 파일 목록
  cd "$LIVE"
  docker compose up -d --remove-orphans
  curl -sf -X POST localhost:9090/-/reload >/dev/null || true
  curl -sf -X POST localhost:9093/-/reload >/dev/null || true
  for svc in loki blackbox grafana; do
    if echo "$1" | grep -q "^$svc/"; then log "$svc 설정 변경 → 재시작"; docker compose restart "$svc"; fi
  done
  return 0
}

health(){  # 기대 대상 수와 비교, 최대 90초 대기
  local exp; exp=$(cat "$STATE.expected" 2>/dev/null || echo 0)
  local up total nr nbad bad L A
  for i in $(seq 1 18); do
    read -r up total < <(targets http://localhost:9090)
    curl -sf -m 3 localhost:3100/ready >/dev/null && L=ok || L=fail
    curl -sf -m 3 localhost:9093/-/ready >/dev/null && A=ok || A=fail
    if [ "$total" -eq "$exp" ] && [ "$up" -eq "$total" ] && [ "$L" = ok ] && [ "$A" = ok ]; then break; fi
    sleep 5
  done
  read -r nr nbad bad < <(rules http://localhost:9090)
  log "상태: 대상 $up/$total (기대 $exp), 규칙 $nr개 (오류 $nbad: $bad), loki $L, alertmanager $A"
  [ "$total" -eq "$exp" ] && [ "$up" -eq "$total" ] && [ "$nbad" -eq 0 ] && [ "$L" = ok ] && [ "$A" = ok ]
}

case "$CMD" in
  prepare)
    [ -n "$SHA" ] || { echo "commit 필요"; exit 2; }
    rm -rf "$STAGE"; git clone -q "$REPO" "$STAGE"; git -C "$STAGE" checkout -q "$SHA"
    cp "$LIVE/.env" "$STAGE/.env"
    log "후보 버전: $(git -C "$STAGE" log -1 --format='%h %s')" ;;
  validate)
    cd "$STAGE"
    docker run --rm -v "$STAGE/prometheus:/etc/prometheus:ro" --entrypoint promtool "$(img prom/prometheus)" check config /etc/prometheus/prometheus.yml
    docker run --rm -v "$STAGE/alertmanager:/etc/alertmanager:ro" --entrypoint amtool "$(img prom/alertmanager)" check-config /etc/alertmanager/alertmanager.yml
    docker run --rm -v "$STAGE/loki:/etc/loki:ro" "$(img grafana/loki)" -config.file=/etc/loki/loki.yml -verify-config
    docker compose config -q
    python3 -c "import yaml,glob; fs=glob.glob('$STAGE/**/*.yml', recursive=True); [yaml.safe_load(open(f)) for f in fs]; print(f'YAML {len(fs)}개 문법 OK')"
    log "검증 통과" ;;
  canary)
    docker rm -f prom-canary >/dev/null 2>&1 || true
    docker run -d --name prom-canary --network monitoring_default -p 127.0.0.1:19090:9090 \
      -v "$STAGE/prometheus:/etc/prometheus:ro" "$(img prom/prometheus)" \
      --config.file=/etc/prometheus/prometheus.yml --storage.tsdb.path=/tmp/data >/dev/null
    log "후보 설정으로 임시 Prometheus 기동, 40초 수집"; sleep 40
    read -r up total < <(targets http://127.0.0.1:19090)
    read -r nr nbad bad < <(rules http://127.0.0.1:19090)
    docker rm -f prom-canary >/dev/null
    log "사전 적용 결과: 대상 $up/$total up, 규칙 $nr개 (오류 $nbad: $bad)"
    if [ "$total" -gt 0 ] && [ "$up" -eq "$total" ] && [ "$nbad" -eq 0 ]; then echo "$total" > "$STATE.expected"; log "사전 적용 통과"
    else log "사전 적용 실패: 운영에 반영하지 않음"; exit 1; fi ;;
  deploy)
    [ -n "$SHA" ] || { echo "commit 필요"; exit 2; }
    cd "$LIVE"; PREV=$(git rev-parse HEAD); echo "$PREV" > "$STATE.prev"
    git fetch -q origin; git reset -q --hard "$SHA"
    CHANGED=$(git diff --name-only "$PREV" "$SHA")
    log "배포 ${PREV:0:7} → ${SHA:0:7}, 변경 파일: $(echo $CHANGED)"
    apply_changes "$CHANGED"; log "배포 반영 완료" ;;
  verify)
    health && log "사후 확인 통과" || { log "사후 확인 실패"; exit 1; } ;;
  rollback)
    PREV=$(cat "$STATE.prev"); cd "$LIVE"; CUR=$(git rev-parse HEAD)
    log "롤백 ${CUR:0:7} → ${PREV:0:7}"
    git reset -q --hard "$PREV"; apply_changes "$(git diff --name-only "$PREV" "$CUR")"
    health && log "롤백 후 정상" || { log "롤백 후에도 비정상: 수동 확인 필요"; exit 1; } ;;
  cleanup)
    docker rm -f prom-canary >/dev/null 2>&1 || true ;;
  *) echo "알 수 없는 단계: $CMD"; exit 2 ;;
esac
