# Audit Scope

Review the supplied snapshot independently.

Primary areas:

1. Docker isolation and mount boundaries
2. Antigravity agent-b filesystem isolation
3. Codex agent-a isolation
4. persistent vs ephemeral state
5. authentication-state confidentiality
6. symlink, junction and path traversal risks
7. prompt-injection exposure
8. fail-open behavior
9. tool permission gaps
10. web-fetch and SSRF risk
11. race conditions / TOCTOU
12. audit evidence integrity
13. oracle blind spots / false positives
14. missing negative tests
15. production blockers

Do not accept previous PASS/CONFIRMED labels as truth without checking
the implementation and evidence.