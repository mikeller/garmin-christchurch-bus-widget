"""Shared exception so every stoptiles module raises and catches one class.

A script run as ``__main__`` and the same file imported by name are distinct
modules, so the exception must not be defined in generate_tiles.py.
"""


class GeneratorError(Exception):
    """A condition that must fail the run with a clear message."""
