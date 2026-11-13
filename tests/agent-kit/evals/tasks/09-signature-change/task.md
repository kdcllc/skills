- id: 09-signature-change
- category: 09-signature-change
- size: medium

## Prompt
money.format_amount(value) always prints dollars. Change it to format_amount(value, currency): the currency argument is required (no default) and the result is the currency code, a space, then the amount with thousands separators and two decimals, for example format_amount(1234.5, "USD") gives "USD 1,234.50". Everything that calls format_amount has to keep working with the new signature: the invoice's total line must use the invoice's own currency field, the receipt line must use the RECEIPT_CURRENCY constant in receipt.py, and the account balance label must use the account's own currency field. Update the existing tests to the new output.

## Decisions
- Find every caller of format_amount in the project, including any that import it under another name.
- Update the existing tests in place rather than deleting them.
