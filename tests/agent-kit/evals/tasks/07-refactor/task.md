- id: 07-refactor
- category: 07-refactor
- size: medium

## Prompt
In report.py the three report functions (sales_report, inventory_report and payroll_report) each repeat the same block of code that formats one report line. Refactor so that block exists only once, as a shared helper the three functions use. The text the reports produce must stay exactly the same, byte for byte, and the three functions keep their names and arguments.

## Decisions
- Keep the shared helper in report.py.
- Keep the existing tests passing; adding tests is optional.
