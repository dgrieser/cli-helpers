(
  "ID\tFROM\tSUBJECT\tDATE\tFLAGS"
),
(
  .[]
  | select(type == "object")
  | . as $msg
  | ($msg.flags | index("Seen") | not) as $unseen
  | (if $unseen then "\u001b[1m" else "" end)
  + "\($msg.id)\t\($msg.from.addr)\t\($msg.subject)\t"
  + ( $msg.date | strptime("%Y-%m-%d %H:%M%z") | strftime("%Y-%m-%dT%H:%M:00Z") )
  + "\t"
  + (if $msg.has_attachment then "📎" else "" end)
  + (if $unseen then "\u001b[0m" else "" end)
)
