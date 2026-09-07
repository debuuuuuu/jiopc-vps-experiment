# Can JioPC Actually Be Used as a VPS?

> A 7-day hands-on investigation into JioPC's compute, storage, networking, development, AI and server capabilities.

I got access to JioPC for 7 days, so instead of just using it as a normal cloud desktop, I decided to test how far I could actually push it.

The main question:

**Can JioPC be used like a VPS, or is it fundamentally a cloud desktop with different limitations?**

I'm testing this by actually running commands, measuring performance, trying to host services, testing networking, and documenting what works and what doesn't.

No assumptions.

No "according to the specs".

Just measurements.

---

## Current Status

**Experiment:** Day 1 / 7

**Current phase:** Reconnaissance

**Status:** 🟢 In progress

---

# Day 1 — Reconnaissance

The first step was understanding what is actually running underneath the JioPC desktop.

## 1. User / Environment

### User

```bash
whoami
id
pwd
