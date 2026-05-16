module PageRoutes
  IDENTITY_PAGES = {
    "about" => {
      title: "About | Big Fluffy Puffy",
      description: "Big Fluffy Puffy is a nonprofit for fireless camp culture in the Pacific Northwest.",
      current_path: "/about",
      kicker: "About",
      heading: "Started by people who still love campfires",
      lead: "Big Fluffy Puffy began as a nudge to friends on long trips: bring enough warmth to stay comfortable when the fire can't happen.",
      rows: [
        ["Origin", "BFP grew out of watching friends be colder than they needed to be on long nights outside. A better puffy, a warmer bag, and a few good habits can change the whole trip."],
        ["The Honest Part", "We love a campfire with whiskey, laughs, and sore legs. The point is not pretending fire is bad. The point is admitting it is increasingly less dependable."],
        ["Why Now", "Climate change is making summers hotter and drier, and long-term forest management has left a lot of dry fuel on the ground. Fire bans are becoming a normal part of camping in the West."],
        ["The Shift", "So we started a thing: a different camping culture where fire bans do not ruin the fun, and where even when fires are allowed but questionable, going without is still fun and comfortable."],
        ["What We Are Building", "BFP tracks fire restrictions and closures so they are easier to know about, pairs them with typical overnight lows, and helps campers understand their no-fire options."],
        ["The Ask", "Join us in protecting what remains of our unburned forests by spreading the message: pack the warmth, skip the fire when you can, and keep the fun intact."]
      ],
      action_href: "/fire-restrictions",
      action_label: "Check Current Restrictions"
    },
    "why-fireless" => {
      title: "Why Fireless | Big Fluffy Puffy",
      description: "Why fireless camping can be prepared, social, warm, and normal.",
      current_path: "/why-fireless",
      kicker: "Why fireless",
      heading: "The fire can't be the plan",
      lead: "Campfires are wonderful when they are legal, safe, and sensible. But more often, they aren't. Big Fluffy Puffy is about bringing enough warmth, light, and atmosphere to keep the night good anyway.",
      rows: [
        ["Risk", "Humans cause most wildfires in the United States, and unattended or poorly managed campfires remain a preventable ignition source."],
        ["Restrictions", "Across the West, hotter summers, dry fuels, smoke, and public land restrictions mean the fire often cannot happen, or probably should not."],
        ["Comfort", "A proper puffy, warm sleep system, hot drink, and good light solve most of what people ask a campfire to do."],
        ["Ritual", "The point is not a colder, quieter camp. Sit closer, pass snacks, tell the long story, and keep the night alive."]
      ],
      action_href: "/fire-restrictions",
      action_label: "See The Monitor"
    },
    "contact" => {
      title: "Contact | Big Fluffy Puffy",
      description: "Contact information for Big Fluffy Puffy.",
      current_path: "/contact",
      kicker: "Contact",
      heading: "Say hello",
      lead: "Email hello@puffy.camp for board, partner, press, and source-correction notes.",
      rows: [
        ["Inbox", "hello@puffy.camp", "mailto:hello@puffy.camp"],
        ["Useful Notes", "Corrections are most helpful when they include the forest, the official source URL, and the line that changed."],
        ["Source Monitor", "Review the current fire restriction monitor.", "/fire-restrictions"]
      ],
      action_href: "mailto:hello@puffy.camp",
      action_label: "Email BFP"
    }
  }.freeze

  def route_pages(r)
    IDENTITY_PAGES.each do |slug, page|
      r.get slug do
        html_response(render_view("pages/identity", page: page))
      end
    end

    r.root do
      html_response(render_view("pages/home"))
    end
  end
end
