"""Plain-text reports for sales, stock and payroll."""


def sales_report(rows):
    """rows: (product, units, unit_price) tuples."""
    lines = ["SALES", "-" * 27]
    total = 0.0
    for product, units, unit_price in rows:
        amount = units * unit_price
        total += amount
        line = str(product)[:12].ljust(12)
        line += str(units).rjust(5)
        line += ("%.2f" % amount).rjust(10)
        lines.append(line)
    lines.append("%-17s%10.2f" % ("TOTAL", total))
    return "\n".join(lines)


def inventory_report(rows):
    """rows: (sku, on_hand, unit_cost) tuples."""
    lines = ["INVENTORY", "-" * 27]
    total = 0.0
    for sku, on_hand, unit_cost in rows:
        amount = on_hand * unit_cost
        total += amount
        line = str(sku)[:12].ljust(12)
        line += str(on_hand).rjust(5)
        line += ("%.2f" % amount).rjust(10)
        lines.append(line)
    lines.append("%-17s%10.2f" % ("STOCK VALUE", total))
    return "\n".join(lines)


def payroll_report(rows):
    """rows: (person, hours, hourly_rate) tuples."""
    lines = ["PAYROLL", "-" * 27]
    total = 0.0
    for person, hours, hourly_rate in rows:
        amount = hours * hourly_rate
        total += amount
        line = str(person)[:12].ljust(12)
        line += str(hours).rjust(5)
        line += ("%.2f" % amount).rjust(10)
        lines.append(line)
    lines.append("%-17s%10.2f" % ("TOTAL PAY", total))
    return "\n".join(lines)
