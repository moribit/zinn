# Security policy

Zinn is early-stage; no supported-version security maintenance window, response SLA or private reporting address is currently published. Do not assume that absence of a report implies safety.

## Reporting

On2026-11-08, GitHub's repository API reported private vulnerability reporting **disabled**. No setting was changed. Before disclosing sensitive information, check whether maintainers have since enabled **Report a vulnerability** in the repository Security area; if available, use that private mechanism. Do not put exploit details, keys or private data in a public issue. If private reporting is unavailable, open a minimal public issue requesting a private contact without disclosing the vulnerability, or wait until maintainers publish a verified channel.

Maintainer setup: follow [GitHub's repository configuration instructions](https://docs.github.com/en/code-security/how-tos/report-and-fix-vulnerabilities/configure-vulnerability-reporting/configure-for-a-repository), currently Settings → Security and quality → Advanced Security → Private vulnerability reporting → Enable. Check access from a non-maintainer account, then update this policy with the verified reporting link. Alternatively publish a monitored contact controlled by maintainers. Never substitute a guessed email or promise an unconfigured channel. No repository security settings are changed by these instructions.

Include affected commit/compiler, input/model provenance, reproduction and impact privately once a channel is established. For ordinary non-sensitive bugs, use the bug issue template.

## Boundaries

UART CRC/checksum/model_id detect accidental corruption/mismatch. They provide **no authentication, encryption or replay protection**. Serial transport and host checkpoint files must be handled within the application's trust boundary. Size/shape checks do not make an untrusted compiler-generated firmware safe. Applications exposed to adversarial inputs need their own validation, access control and resource limits. No physical safety or security certification is claimed.
