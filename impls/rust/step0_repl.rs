use std::io::Write;

fn main() -> std::io::Result<()> {    
    loop {
        write!(std::io::stdout(), "user> ")?;
        std::io::stdout().flush()?;
        let mut line = String::new();
        let bytes = std::io::stdin().read_line(&mut line)?;
        let input = line.trim();

        // Handle EOF/Ctrl+D.
        if bytes == 0 {
            break;
        }

        writeln!(std::io::stdout(), "{}", rep(input))?;
    }
    Ok(())
}

fn read(s: &str) -> &str {
    s
}

fn eval(s: &str) -> &str {
    s
}

fn print(s: &str) -> &str {
    s
}

fn rep(s: &str) -> &str {
    print(eval(read(s)))
}
