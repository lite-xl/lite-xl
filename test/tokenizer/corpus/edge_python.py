"""Module docstring
spanning several lines with a stray ''' inside.
"""
import re
from typing import Optional


def f(x: int, *args, **kwargs) -> Optional[str]:
    # a comment
    s = f"interpolated {x!r:>{width}} value"
    r = r"raw \d+ string"
    b = b'\x00bytes'
    t = ("implicit"
         "concatenation")
    return s or r or t


class A:
    attr = 1

    @property
    def p(self):
        return self.attr


# a string that is opened but never closed before EOF
leftover = """this docstring never terminates
