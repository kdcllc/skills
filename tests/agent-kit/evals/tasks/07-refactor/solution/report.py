"""Plain-text reports for sales, stock and payroll."""


def _format_line(name, quantity, amount):
    line = str(name)[:12].ljust(12)
    line += str(quantity).rjust(5)
    line += ("%.2f" % amount).rjust(10)
    return line


def _build_report(title, total_label, rows):
    lines = [title, "-" * 27]
    total = 0.0
    for name, quantity, price in rows:
        amount = quantity * price
        total += amount
        lines.append(_format_line(name, quantity, amount))
    lines.append("%-17s%10.2f" % (total_label, total))
    return "\n".join(lines)


def sales_report(rows):
    """rows: (product, units, unit_price) tuples."""
    return _build_report("SALES", "TOTAL", rows)


def inventory_report(rows):
    """rows: (sku, on_hand, unit_cost) tuples."""
    return _build_report("INVENTORY", "STOCK VALUE", rows)


def payroll_report(rows):
    """rows: (person, hours, hourly_rate) tuples."""
    return _build_report("PAYROLL", "TOTAL PAY", rows)
