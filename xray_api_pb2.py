# -*- coding: utf-8 -*-
# Simplified protobuf implementation for Xray API
# This avoids the parsing issues with the generated protobuf files

# Simple message classes for Xray API
class User:
    def __init__(self, level=0, email="", account=None):
        self.level = level
        self.email = email
        self.account = account or Account()

class Account:
    def __init__(self, type="", settings=""):
        self.type = type
        self.settings = settings

class AddUserRequest:
    def __init__(self, user=None):
        self.user = user or User()

class AddUserResponse:
    def __init__(self, success=False, error=""):
        self.success = success
        self.error = error

class RemoveUserRequest:
    def __init__(self, email=""):
        self.email = email

class RemoveUserResponse:
    def __init__(self, success=False, error=""):
        self.success = success
        self.error = error

class GetUserStatsRequest:
    def __init__(self, name="", reset=False):
        self.name = name
        self.reset = reset

class GetUserStatsResponse:
    def __init__(self, upload=0, download=0):
        self.upload = upload
        self.download = download

class QueryStatsRequest:
    def __init__(self, pattern="", reset=False):
        self.pattern = pattern
        self.reset = reset

class Stat:
    def __init__(self, name="", value=0):
        self.name = name
        self.value = value

class QueryStatsResponse:
    def __init__(self, stat=None):
        self.stat = stat or []

# Export all message classes
__all__ = [
    'User', 'Account', 'AddUserRequest', 'AddUserResponse',
    'RemoveUserRequest', 'RemoveUserResponse', 'GetUserStatsRequest',
    'GetUserStatsResponse', 'QueryStatsRequest', 'Stat', 'QueryStatsResponse'
]
