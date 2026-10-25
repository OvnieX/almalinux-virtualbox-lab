#!/usr/bin/env python3
"""Tests Linux/Bash isoles du controle noyau genere ; aucun systemctl reel."""
import subprocess
import tempfile
from pathlib import Path

source = Path(__file__).with_name('New-AnsibleLab.ps1').read_text()
start = source.index('lab_check_kernel() {')
end = source.index('\nlab_check_kernel\n# Verifier la syntaxe SSH', start)
functions = source[start:end]
cases = [
    ('Boot normal', 'KERNEL_NO_ALERT_DETECTED', True),
    ('WARNING: CPU: 1 at rcu_sched_clock_irq\nCall Trace:', 'KERNEL_WARNINGS', True),
    ('Call Trace:', 'KERNEL_WARNINGS', True),
    ('rcu: detected stalls on CPUs', 'KERNEL_WARNINGS', True),
    ('WARNING: CPU: 1\nOops: fatal', 'KERNEL_ERROR', False),
    ('BUG: unable to handle page fault', 'KERNEL_ERROR', False),
    ('Kernel panic - not syncing', 'KERNEL_ERROR', False),
    ('general protection fault', 'KERNEL_ERROR', False),
    ('watchdog: BUG: soft lockup', 'KERNEL_ERROR', False),
]
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    state = root / 'state'
    state.mkdir()
    motd = root / 'motd'
    log = root / 'input'
    body = functions.replace('/var/lib/lab-bootstrap', str(state)).replace('/etc/motd', str(motd))
    prefix = 'set -Eeuo pipefail\njournalctl() { cat "' + str(log) + '"; }\n'
    for role in ('NODE_READY', 'ANSIBLE_READY'):
        for message, expected, success in cases:
            for item in state.iterdir():
                item.unlink()
            motd.write_text('VM configuree\n')
            log.write_text(message + '\n')
            result = subprocess.run(['bash'], input=prefix + body + '\nlab_publish_ready ' + role,
                                    text=True, capture_output=True)
            assert (result.returncode == 0) == success, (message, result)
            assert (state / 'kernel-status').read_text().strip() == expected
            assert (state / 'kernel-current-boot.log').read_text() == log.read_text()
            assert (state / 'done').exists() == success
            if success:
                assert (state / 'status').read_text().strip() == role
                assert ('AVERTISSEMENT NOYAU' in motd.read_text()) == (expected == 'KERNEL_WARNINGS')
            else:
                assert not (state / 'status').exists()
                assert role not in result.stdout, 'READY affiche avant la validation'
    # Aucun READY si journalctl echoue, ou si un controle fonctionnel precedent echoue.
    for extra in ('journalctl() { return 1; }\nlab_publish_ready NODE_READY',
                  'false\nlab_publish_ready NODE_READY'):
        for item in state.iterdir():
            item.unlink()
        result = subprocess.run(['bash'], input=prefix + body + '\n' + extra,
                                text=True, capture_output=True)
        assert result.returncode != 0 and not (state / 'done').exists()
        assert not (state / 'status').exists()
print('OK : 18 cas noyau/role, journal conserve, avertissement MOTD, erreurs bloquantes et publication finale.')
