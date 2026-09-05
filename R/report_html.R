# ---- Minimal SVG helpers ---------------------------------------------------
#
# The charts are written by hand rather than through a plotting package. A model
# card should be one self-contained file that can be mailed or committed, and
# every drawing here is a handful of lines and rectangles. Bringing in a
# plotting dependency to draw them would cost more than it saves.

html_escape <- function(x) {
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  x <- gsub(">", "&gt;", x, fixed = TRUE)
  gsub("\"", "&quot;", x, fixed = TRUE)
}

svg_text <- function(x, y, label, anchor = "middle", size = 11, fill = "#444") {
  sprintf(
    '<text x="%.1f" y="%.1f" text-anchor="%s" font-size="%d" fill="%s">%s</text>',
    x, y, anchor, size, fill, html_escape(label)
  )
}

svg_frame <- function(w, h, pad, title, xlab, ylab, body) {
  c(
    sprintf(
      paste0(
        '<svg viewBox="0 0 %d %d" width="100%%" ',
        'style="max-width:%dpx;height:auto" role="img" aria-label="%s" ',
        'xmlns="http://www.w3.org/2000/svg">'
      ),
      w, h, w, html_escape(title)
    ),
    sprintf("<title>%s</title>", html_escape(title)),
    sprintf(
      '<rect x="%d" y="%d" width="%d" height="%d" fill="none" stroke="#ccc"/>',
      pad, pad, w - 2 * pad, h - 2 * pad
    ),
    body,
    svg_text(w / 2, h - 6, xlab),
    sprintf(
      paste0(
        '<text x="12" y="%.1f" text-anchor="middle" font-size="11" ',
        'fill="#444" transform="rotate(-90 12 %.1f)">%s</text>'
      ),
      h / 2, h / 2, html_escape(ylab)
    ),
    "</svg>"
  )
}

# ---- Charts ----------------------------------------------------------------

svg_reliability <- function(bins) {
  if (is.null(bins) || !length(bins$confidence)) {
    return(NULL)
  }
  w <- 320
  h <- 260
  pad <- 34
  sx <- function(v) pad + v * (w - 2 * pad)
  sy <- function(v) (h - pad) - v * (h - 2 * pad)

  body <- c(
    # perfect calibration
    sprintf(
      '<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#bbb" stroke-dasharray="4 3"/>',
      sx(0), sy(0), sx(1), sy(1)
    ),
    sprintf(
      '<polyline fill="none" stroke="#1f6feb" stroke-width="2" points="%s"/>',
      paste(sprintf("%.1f,%.1f", sx(bins$confidence), sy(bins$observed)), collapse = " ")
    ),
    sprintf(
      paste0(
        '<circle cx="%.1f" cy="%.1f" r="3" fill="#1f6feb">',
        "<title>confidence %.3f, observed %.3f, n %d</title></circle>"
      ),
      sx(bins$confidence), sy(bins$observed),
      bins$confidence, bins$observed, as.integer(bins$n)
    ),
    svg_text(sx(0), h - pad + 14, "0", size = 10),
    svg_text(sx(1), h - pad + 14, "1", size = 10),
    svg_text(pad - 10, sy(0), "0", anchor = "end", size = 10),
    svg_text(pad - 10, sy(1) + 4, "1", anchor = "end", size = 10)
  )
  svg_frame(w, h, pad, "Reliability diagram", "predicted probability", "observed frequency", body)
}

svg_coverage <- function(curve, alpha) {
  if (is.null(curve) || !length(curve$alpha)) {
    return(NULL)
  }
  w <- 320
  h <- 260
  pad <- 34
  target <- 1 - curve$alpha
  sx <- function(v) pad + v * (w - 2 * pad) / max(curve$alpha)
  sy <- function(v) (h - pad) - v * (h - 2 * pad)

  body <- c(
    sprintf(
      '<polyline fill="none" stroke="#bbb" stroke-dasharray="4 3" points="%s"/>',
      paste(sprintf("%.1f,%.1f", sx(curve$alpha), sy(target)), collapse = " ")
    ),
    sprintf(
      '<polyline fill="none" stroke="#1f6feb" stroke-width="2" points="%s"/>',
      paste(sprintf("%.1f,%.1f", sx(curve$alpha), sy(curve$coverage)), collapse = " ")
    ),
    sprintf(
      '<line x1="%.1f" y1="%d" x2="%.1f" y2="%d" stroke="#d1242f" stroke-width="1"/>',
      sx(alpha), pad, sx(alpha), h - pad
    ),
    svg_text(sx(alpha), pad - 4, sprintf("alpha = %.2f", alpha), size = 10, fill = "#d1242f"),
    svg_text(sx(0), h - pad + 14, "0", size = 10),
    svg_text(sx(max(curve$alpha)), h - pad + 14, sprintf("%.2f", max(curve$alpha)), size = 10),
    svg_text(pad - 10, sy(0), "0", anchor = "end", size = 10),
    svg_text(pad - 10, sy(1) + 4, "1", anchor = "end", size = 10)
  )
  svg_frame(
    w, h, pad, "Empirical coverage against the target",
    "alpha", "coverage", body
  )
}

svg_bars <- function(values, threshold, title, xlab) {
  values <- values[is.finite(values)]
  if (!length(values)) {
    return(NULL)
  }
  w <- 320
  pad <- 34
  h <- max(140, 2 * pad + 22 * length(values))
  top <- max(c(values, threshold), na.rm = TRUE) * 1.15
  if (!is.finite(top) || top <= 0) top <- 1
  bw <- function(v) (v / top) * (w - 2 * pad)
  rows <- seq_along(values)
  ycent <- pad + (rows - 0.5) * ((h - 2 * pad) / length(values))

  body <- c(
    sprintf(
      '<rect x="%d" y="%.1f" width="%.1f" height="12" fill="%s"><title>%s: %.3f</title></rect>',
      pad, ycent - 6, pmax(bw(values), 0.5),
      ifelse(values > threshold, "#d1242f", "#1f6feb"),
      html_escape(names(values)), values
    ),
    svg_text(pad + 4, ycent + 4, names(values), anchor = "start", size = 10, fill = "#fff"),
    sprintf(
      '<line x1="%.1f" y1="%d" x2="%.1f" y2="%d" stroke="#d1242f" stroke-dasharray="3 2"/>',
      pad + bw(threshold), pad, pad + bw(threshold), h - pad
    )
  )
  svg_frame(w, h, pad, title, xlab, "", body)
}

# ---- HTML document ---------------------------------------------------------

status_badge <- function(s) {
  colour <- switch(s,
    pass = "#1a7f37",
    weak = "#9a6700",
    fail = "#d1242f",
    waived = "#9a6700",
    info = "#57606a",
    "#57606a"
  )
  sprintf(
    paste0(
      '<span style="background:%s;color:#fff;border-radius:3px;',
      'padding:1px 6px;font-size:11px">%s</span>'
    ),
    colour, html_escape(s)
  )
}

report_html <- function(x, newdata = NULL) {
  ce <- x$certificate
  res <- ce$results

  rows <- vapply(res, function(r) {
    ci <- r$ci
    ci_txt <- if (is.null(ci) || length(ci) != 2 || anyNA(ci)) {
      ""
    } else {
      sprintf("[%s, %s]", fmt_num(ci[1]), fmt_num(ci[2]))
    }
    sprintf(
      "<tr><td><code>%s</code></td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>",
      html_escape(r$id), status_badge(r$status), fmt_num(r$statistic),
      ci_txt, fmt_num(r$threshold), html_escape(r$message)
    )
  }, character(1))

  charts <- c(
    svg_reliability(res$calib_ece$evidence$bins),
    svg_coverage(res$conformal_split$evidence$curve, res$conformal_split$evidence$alpha %||% 0.1)
  )

  shift_block <- character(0)
  if (!is.null(newdata)) {
    sh <- shift_eval(x$shift, as.data.frame(newdata), x$features)
    psi <- sh$batch_psi
    if (length(psi) && any(is.finite(psi))) {
      bar <- suppressWarnings(max(sh$effective_threshold, na.rm = TRUE))
      shift_block <- c(
        "<h2>Shift on the supplied batch</h2>",
        sprintf(
          "<p>%d rows. Flagged features: %s.</p>", nrow(newdata),
          if (length(sh$batch_flagged)) {
            html_escape(paste(sh$batch_flagged, collapse = ", "))
          } else {
            "none"
          }
        ),
        svg_bars(psi, bar, "Population stability index by feature", "PSI")
      )
    }
  }

  waiver_block <- if (is.null(ce$waivers)) {
    character(0)
  } else {
    c(
      "<h2>Waivers</h2>",
      sprintf(
        "<p class=\"warn\"><strong>%s</strong> waived. Reason given: %s</p>",
        html_escape(paste(ce$waivers$ids, collapse = ", ")),
        html_escape(ce$waivers$reason)
      )
    )
  }

  c(
    "<!DOCTYPE html>", "<html lang=\"en\"><head><meta charset=\"utf-8\">",
    sprintf("<title>Model card: %s</title>", html_escape(ce$outcome)),
    "<style>",
    "body{font-family:system-ui,-apple-system,Segoe UI,Helvetica,Arial,sans-serif;",
    "max-width:820px;margin:2rem auto;padding:0 1rem;color:#1f2328;line-height:1.5}",
    "table{border-collapse:collapse;width:100%;font-size:14px}",
    "th,td{border-bottom:1px solid #d0d7de;padding:6px 8px;text-align:left;vertical-align:top}",
    "th{background:#f6f8fa}",
    "code{background:#f6f8fa;padding:1px 4px;border-radius:3px;font-size:13px}",
    ".meta{color:#57606a;font-size:14px}",
    ".charts{display:flex;flex-wrap:wrap;gap:1.5rem;margin:1rem 0}",
    ".warn{background:#fff8c5;border-left:4px solid #9a6700;padding:.5rem .75rem}",
    "</style></head><body>",
    sprintf(
      "<h1>Model card: %s <span class=\"meta\">(%s)</span></h1>",
      html_escape(ce$outcome), html_escape(ce$task)
    ),
    sprintf(
      paste0(
        "<p class=\"meta\">Certificate <code>%s</code>, issued %s UTC, ",
        "status <strong>%s</strong> (on_fail <code>%s</code>), attest %s.</p>"
      ),
      html_escape(ce$id), html_escape(ce$issued), html_escape(ce$status),
      html_escape(ce$on_fail), html_escape(ce$attest_version)
    ),
    "<ul class=\"meta\">",
    sprintf("<li>Engine: <code>%s</code></li>", html_escape(ce$engine)),
    sprintf(
      "<li>Split: <code>%s</code> &mdash; train %d / calib %d / test %d</li>",
      html_escape(ce$split), ce$n[["train"]], ce$n[["calib"]], ce$n[["test"]]
    ),
    sprintf(
      "<li>Features (%d): %s</li>", length(ce$features),
      paste0("<code>", html_escape(ce$features), "</code>", collapse = ", ")
    ),
    sprintf(
      "<li>Hashes: data <code>%s</code>, spec <code>%s</code>, model <code>%s</code></li>",
      substr(ce$hashes$data, 1, 12), substr(ce$hashes$spec, 1, 12),
      substr(ce$hashes$model, 1, 12)
    ),
    "</ul>",
    "<h2>Checks</h2>",
    "<table><thead><tr><th>check</th><th>status</th><th>statistic</th>",
    "<th>95% CI</th><th>threshold</th><th>detail</th></tr></thead><tbody>",
    rows,
    "</tbody></table>",
    waiver_block,
    if (length(charts)) {
      c("<h2>Diagnostics</h2>", "<div class=\"charts\">", charts, "</div>")
    } else {
      character(0)
    },
    shift_block,
    "<h2>Refusal policy</h2>",
    "<p>Rows with any numeric feature outside the training support (widened by",
    "tolerance) or an unseen categorical level are refused. Batches with feature",
    "PSI above the threshold are flagged.</p>",
    "</body></html>"
  )
}
