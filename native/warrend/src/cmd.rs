//! Execution seam for the external network-recovery commands (`nft`, `pfctl`,
//! `networksetup`).
//!
//! Mirrors the engine's `CommandRunner` pattern (warrenguard-killswitch-os):
//! production shells out, tests inject a recorder so the recovery / lockdown /
//! revert lifecycles are verified behaviorally, without privileges, on any
//! host. Synchronous on purpose: the callers run at startup, in the CLI escape
//! path, and on shutdown, none of which are hot paths; async call sites wrap
//! invocations in `spawn_blocking`.

/// Outcome of one command, reduced to what the recovery paths need. Unlike the
/// engine's variant this keeps stdout too: stale-rule detection reads rule
/// listings and the macOS DNS reconcile parses `networksetup` output.
#[derive(Debug, Clone)]
pub struct CmdOutput {
    /// `true` iff the process exited with status 0.
    pub success: bool,
    /// Captured stdout (lossy UTF-8).
    pub stdout: String,
    /// Captured stderr (lossy UTF-8). Feeds the "already absent" idempotence
    /// checks on teardown.
    pub stderr: String,
}

/// Runs one external command to completion.
pub trait CmdRunner: Send + Sync {
    /// Whether the commands run as root, the only account that installs the
    /// artifacts the recovery paths clear.
    fn privileged(&self) -> bool;

    /// Run `program` with `args`, optionally piping `stdin` into it, and wait.
    ///
    /// # Errors
    ///
    /// `std::io::Error` when the process cannot be spawned or its pipes fail.
    /// A non-zero exit status is NOT an `Err`; it is reported through
    /// [`CmdOutput::success`].
    fn run(&self, program: &str, args: &[&str], stdin: Option<&str>) -> std::io::Result<CmdOutput>;
}

/// Production [`CmdRunner`]: spawns the real process.
#[derive(Debug, Default, Clone, Copy)]
pub struct SystemRunner;

impl CmdRunner for SystemRunner {
    fn privileged(&self) -> bool {
        // SAFETY: geteuid has no preconditions.
        unsafe { libc::geteuid() == 0 }
    }

    fn run(&self, program: &str, args: &[&str], stdin: Option<&str>) -> std::io::Result<CmdOutput> {
        use std::io::Write as _;
        use std::process::{Command, Stdio};

        let mut command = Command::new(program);
        command
            .args(args)
            .stdin(if stdin.is_some() {
                Stdio::piped()
            } else {
                Stdio::null()
            })
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        let mut child = command.spawn()?;
        if let Some(content) = stdin {
            let mut pipe = child
                .stdin
                .take()
                .ok_or_else(|| std::io::Error::other("child stdin pipe missing"))?;
            pipe.write_all(content.as_bytes())?;
            drop(pipe);
        }
        let out = child.wait_with_output()?;
        Ok(CmdOutput {
            success: out.status.success(),
            stdout: String::from_utf8_lossy(&out.stdout).into_owned(),
            stderr: String::from_utf8_lossy(&out.stderr).into_owned(),
        })
    }
}

#[cfg(test)]
pub(crate) mod testing {
    use super::{CmdOutput, CmdRunner};
    use std::sync::Mutex;

    /// One recorded invocation: (program, args, stdin).
    pub type RecordedCall = (String, Vec<String>, Option<String>);

    /// Recording [`CmdRunner`] whose reply for each call is scripted by a
    /// match on (program, first args); unmatched calls succeed with empty
    /// output.
    #[derive(Default)]
    pub struct RecordingRunner {
        calls: Mutex<Vec<RecordedCall>>,
        /// (program, arg fragment that must appear, reply) triples; first
        /// match wins.
        replies: Vec<(String, String, CmdOutput)>,
        /// Reports itself unprivileged (a root runner by default).
        unprivileged: bool,
    }

    impl RecordingRunner {
        pub fn unprivileged(mut self) -> Self {
            self.unprivileged = true;
            self
        }

        pub fn with_reply(mut self, program: &str, arg_fragment: &str, reply: CmdOutput) -> Self {
            self.replies
                .push((program.to_owned(), arg_fragment.to_owned(), reply));
            self
        }

        pub fn calls(&self) -> Vec<RecordedCall> {
            self.calls.lock().expect("runner mutex").clone()
        }
    }

    /// A successful reply carrying `stdout`.
    pub fn ok_with(stdout: &str) -> CmdOutput {
        CmdOutput {
            success: true,
            stdout: stdout.to_owned(),
            stderr: String::new(),
        }
    }

    /// A failed reply carrying `stderr`.
    pub fn fail_with(stderr: &str) -> CmdOutput {
        CmdOutput {
            success: false,
            stdout: String::new(),
            stderr: stderr.to_owned(),
        }
    }

    impl CmdRunner for RecordingRunner {
        fn privileged(&self) -> bool {
            !self.unprivileged
        }

        fn run(
            &self,
            program: &str,
            args: &[&str],
            stdin: Option<&str>,
        ) -> std::io::Result<CmdOutput> {
            self.calls.lock().expect("runner mutex").push((
                program.to_owned(),
                args.iter().map(|s| (*s).to_owned()).collect(),
                stdin.map(str::to_owned),
            ));
            let joined = args.join(" ");
            for (prog, fragment, reply) in &self.replies {
                if prog == program && joined.contains(fragment.as_str()) {
                    return Ok(reply.clone());
                }
            }
            Ok(ok_with(""))
        }
    }
}
