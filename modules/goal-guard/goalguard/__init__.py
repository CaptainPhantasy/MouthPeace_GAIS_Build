"""Goal Guard — a headless, model- and harness-agnostic drift controller.

It anchors a run's original goal, judges current work against it at checkpoints,
and (per the trust ladder) observes, suggests, asks, or auto-corrects — escalating
only when it cannot recover. It supervises other agents; you never chat with it.
"""

__version__ = "0.1.0"
