# api OOMKilled under a 64Mi limit without GOMEMLIMIT

Date: 2026-11-11 · Type: controlled experiment, local k3d cluster `jobtracker`

## What was misconfigured

The api container had `limits.memory: 64Mi` and no `GOMEMLIMIT`. The Go runtime
does not know about the cgroup limit: with the default `GOGC=100` it lets the heap
grow to about twice the live heap before collecting.

To produce load, a temporary unauthenticated endpoint `GET /debug/alloc?live=N&garbage=M`
was added on a throwaway branch (never merged). It holds `N` MiB live for the
request and allocates `M` MiB of short-lived garbage, touching every page so the
memory counts toward the container's usage.

## Impact

One request, `live=35&garbage=200`, killed the pod that received it:

```
api-d949b4fcb-nzrnv   RESTARTS 1
lastState.terminated: reason=OOMKilled exitCode=137 finishedAt=2026-11-11T10:00:07Z
```

- Idle memory before the request was 7–9 Mi (`kubectl top`): about an eighth of
  the limit. A single request was enough to kill the pod.
- The client got `curl: (52) Empty reply from server`.
- An OOMKill is a SIGKILL. The graceful shutdown path (readiness flip,
  pre-shutdown wait, draining) never ran, so every in-flight request on that pod
  was dropped.
- The second replica (`zvm8z`, RESTARTS 0) kept serving. With one replica this
  would have been an outage.

## Where the evidence is

- **Container status**, not events: `kubectl describe pod` → `Last State:
  Terminated, Reason: OOMKilled, Exit Code: 137`. `kubectl get events` showed no
  "OOMKilled". `Last State` keeps only the most recent restart, so save it right
  away.
- `kubectl logs --previous`: the logs just stop. SIGKILL leaves the process no
  chance to log anything.
- **An empty reply on its own proves nothing.** One rerun also returned
  `Empty reply from server` but killed nothing: the port-forward had failed
  (`bind: address already in use`, because the k3d load balancer publishes host
  port 8080), so curl hit the load balancer instead of the api. Always confirm with
  RESTARTS and `lastState`.

## Why it happened

With ~36 MB live, the default heap goal is ~72 MB, which is above the 64Mi cgroup
limit. The kernel kills the process before the GC runs. The memory that pushed it
over was garbage the GC would have freed if it had run earlier.

## Fix

`GOMEMLIMIT=54MiB` (~85% of the limit; the rest is headroom for memory the Go
runtime does not count). It is a soft limit: near it, the GC runs more often
instead of letting the heap grow.

Same request with the fix, with `GODEBUG=gctrace=1` on
(pod `api-6447878d7b-72779`):

```
{"msg":"request","path":"/debug/alloc","status":200,"duration_ms":135}
gc 5  @253.247s 0%: ... 45->45->36 MB, 45 MB goal, ...
gc 22 @253.305s 0%: ... 43->50->43 MB, 41 MB goal, ...
gc 28 @253.329s 0%: ... 45->45->36 MB, 45 MB goal, ...
```

- The heap goal stayed at 41–45 MB instead of ~72 MB. The goal covers the heap
  only, while GOMEMLIMIT covers all runtime memory, so the goal sits below 54.
- 24 collections in ~80 ms, peak heap 50 MB, RESTARTS stayed 0, and the request
  returned 200.

## What the fix does not cover

Live memory above the limit. `live=70&garbage=0` on the same pod with GOMEMLIMIT
still ended in `OOMKilled`, exit 137, at 2026-11-11T11:05:13Z. The trace shows
the GC running back-to-back while the live heap kept growing (`41->41->41`,
`48->48->48`, `56->56->56 MB`) until the kernel killed it. The GC cannot free
memory that is still referenced. For that, the fix is a bigger limit or finding
what holds the memory, not GOMEMLIMIT.

## Follow-up

- Final: limits.memory: 256Mi, GOMEMLIMIT=220MiB.
- Remove `GODEBUG=gctrace=1`.
- Delete the `/debug/alloc` branch. It is a public endpoint that lets anyone grow
  memory on demand.
