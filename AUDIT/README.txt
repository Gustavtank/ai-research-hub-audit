AI_RESEARCH_HUB - SECURITY AUDIT
================================

PURPOSE
-------

This directory stores sanitized technical evidence related to
security, isolation, permissions, failures, limitations and
observed behavior of the AI_RESEARCH_HUB.

It exists so that independent AI systems or human reviewers can
audit the security architecture without receiving credentials,
personal information or the complete research repository.


CONTENT RULES
-------------

ALLOWED:

- relevant PowerShell commands
- relevant stdout/stderr excerpts
- exit codes
- software versions
- model names
- test results
- observed filesystem behavior
- isolation behavior
- security limitations
- hashes
- documented vs observed differences
- remediation decisions

FORBIDDEN:

- personal names
- personal email addresses
- passwords
- OAuth tokens
- API keys
- cookies
- auth.json contents
- recovery codes
- account identifiers
- private conversation contents unrelated to security
- unnecessary absolute user profile paths


SANITIZATION
------------

Examples:

C:\Users\<REDACTED_USER>\...  -> %USERPROFILE%\...

temporary directories   -> %TEMP%\...

email                    -> <REDACTED_EMAIL>

token / secret           -> <REDACTED_SECRET>

session IDs              -> omit unless technically required


TRUST MODEL
-----------

Information in this directory must distinguish:

[CONFIRMED]
Observed and independently verified.

[TEST]
Currently under validation.

[LIMITATION]
Known technical limitation.

[ERROR]
Observed failure.

[INFERENCE]
Reasonable interpretation that is not independently proven.

[PENDING]
Not yet validated.


IMPORTANT
---------

This directory is operational audit evidence.

It must NOT be treated as canonical KNOWLEDGE.

It must NOT contain credentials.

It should NOT be committed to a public or private Git repository
without an explicit security review.

Agents should eventually receive this directory as READ-ONLY.

A Windows ACL alone is NOT considered sufficient isolation while
an AI process runs under the same Windows user identity.

The final protection boundary must come from the isolated runtime,
container or equivalent security boundary.

Created UTC:
2026-08-20T11:42:09Z