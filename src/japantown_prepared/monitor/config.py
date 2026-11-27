import logging
import os
import tomllib

from dotenv import load_dotenv

from . import logger

load_dotenv()

config_file = os.environ.get("MONITOR_CONFIG_FILE", "config.toml")

with open(config_file, "rb") as f:
    config = tomllib.load(f)

config.setdefault("service", {})
config["service"].setdefault("cache_directory", "~/.cache/japantown_prepared_monitor")
config["service"].setdefault("cache_expiry_in_seconds", 600)
config["service"].setdefault("log_level", "WARN")
config["service"].setdefault("http_timeout_in_seconds", 20)
config["service"].setdefault("interval", "15m")

config.setdefault("notify", {})
config["notify"].setdefault("enable", False)
config["notify"].setdefault("smtp_host", "localhost")
config["notify"].setdefault("smtp_port", 25)
config["notify"].setdefault("ssl", False)

logger.setLevel(logging.getLevelName(config["service"]["log_level"].upper()))
