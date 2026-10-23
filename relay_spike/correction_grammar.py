"""Shared surface correction forms for ASR intent and durable task state.

This only recognizes a correction signal. It does not resolve its target or
meaning; the task record must require clarification for an unsupported tail.
"""
import re

CORRECTION_PREFIX = re.compile(
    r'^(?:no\b|actually\b|instead\b|sorry[, ]|i meant\b|'
    r'make that\b|rather\b|let me rephrase\b|correction\b)[\s,:-]*',re.I
)
