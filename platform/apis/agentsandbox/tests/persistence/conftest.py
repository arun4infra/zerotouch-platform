#!/usr/bin/env python3
"""
Conftest for persistence tests - imports fixtures from parent directory
"""

# Import all fixtures from parent conftest
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from conftest import *