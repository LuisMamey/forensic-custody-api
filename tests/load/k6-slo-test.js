import http from 'k6/http';
import { check, sleep } from 'k6';

// 1. Simulation options & SRE SLO Thresholds
export const options = {
  stages: [
    { duration: '5s', target: 10 },  // Ramp-up to 10 concurrent forensic investigators
    { duration: '15s', target: 20 }, // Stress plateau with 20 concurrent users
    { duration: '5s', target: 0 },   // Ramp-down to 0
  ],
  thresholds: {
    // SLO 1: Availability >= 99.9% (error rate < 0.1%)
    http_req_failed: ['rate<0.001'],
    // SLO 2: Evidence Read Latency p99 < 250ms
    http_req_duration: ['p(99)<250'],
    // General check pass rate >= 99%
    checks: ['rate>0.99'],
  },
};

const BASE_URL = __ENV.TARGET_URL || 'http://localhost:8080';

export default function () {
  // Test 1: Health probe validation
  const healthRes = http.get(`${BASE_URL}/health`);
  check(healthRes, {
    'health status is 200': (r) => r.status === 200,
    'health body is ok': (r) => r.body === 'ok',
  });

  // Read authorization token from environment variable
  const authToken = __ENV.AUTH_TOKEN || '';
  const params = {
    headers: {
      'Authorization': `Bearer ${authToken}`,
      'Content-Type': 'application/json',
    },
  };

  const casesRes = http.get(`${BASE_URL}/cases`, params);
  check(casesRes, {
    'cases status is 200': (r) => r.status === 200,
  });

  // Test 3: Prometheus Metrics endpoint availability
  const metricsRes = http.get(`${BASE_URL}/metrics`);
  check(metricsRes, {
    'metrics status is 200': (r) => r.status === 200,
    'metrics contains telemetry': (r) => r.body.includes('forensic_http_requests_total'),
  });

  sleep(0.1); // 100ms think time between investigator operations
}
