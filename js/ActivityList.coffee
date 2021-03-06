class ActivityList extends Class
	constructor: ->
		@activities = null
		@directories = []
		@need_update = true
		@limit = 10
		@loading = true

	queryActivities: (cb) ->
		directories_sql = ("'#{directory}'" for directory in @directories).join(",")
		query = """
			SELECT
			 'comment' AS type, json.*,
			 json.site || "/" || post_uri AS subject, body, date_added,
			 NULL AS subject_auth_address, NULL AS subject_hub, NULL AS subject_user_name
			FROM
			 json
			LEFT JOIN comment USING (json_id)
			WHERE
			 json.directory IN (#{directories_sql})

			UNION ALL

			SELECT
			 'post_like' AS type, json.*,
			 json.site || "/" || post_uri AS subject, '' AS body, date_added,
			 NULL AS subject_auth_address, NULL AS subject_hub, NULL AS subject_user_name
			FROM
			 json
			LEFT JOIN post_like USING (json_id)
			WHERE
			 json.directory IN (#{directories_sql})

			UNION ALL

			SELECT
			 'follow' AS type, json.*,
			 follow.hub || "/" || follow.auth_address AS subject, '' AS body, date_added,
			 follow.auth_address AS subject_auth_address, follow.hub AS subject_hub, follow.user_name AS subject_user_name
			FROM
			 json
			LEFT JOIN follow USING (json_id)
			WHERE
			 json.directory IN (#{directories_sql})
			ORDER BY date_added DESC
			LIMIT #{@limit+1}
		"""
		Page.cmd "dbQuery", [query, {directories: @directories}], (rows) =>
			# Resolve subject's name
			directories = []
			rows = (row for row in rows when row.subject)  # Remove deleted users activities
			for row in rows
				row.auth_address = row.directory.replace("data/users/", "")
				subject_address = row.subject.replace(/_.*/, "").replace(/.*\//, "")  # Only keep user's address
				row.subject_address = subject_address
				directory = "data/users/#{subject_address}"
				if directory not in directories
					directories.push directory

			Page.cmd "dbQuery", ["SELECT * FROM json WHERE ?", {directory: directories}], (subject_rows) =>
				# Add subject node to rows
				subject_db = {}
				for subject_row in subject_rows
					subject_row.auth_address = subject_row.directory.replace("data/users/", "")
					subject_db[subject_row.auth_address] = subject_row
				for row in rows
					row.subject = subject_db[row.subject_address]
					row.subject ?= {}
					row.subject.auth_address ?= row.subject_auth_address
					row.subject.hub ?= row.subject_hub
					row.subject.user_name ?= row.subject_user_name
				cb(rows)


	update: =>
		@need_update = false
		@loading = true
		@queryActivities (res) =>
			@activities = res
			@loading = false
			Page.projector.scheduleRender()

	handleMoreClick: =>
		@limit += 20
		@update()
		return false

	renderActivity: (activity) ->
		if not activity.subject.user_name
			return
		activity_user_link = "?Profile/#{activity.hub}/#{activity.auth_address}/#{activity.cert_user_id}"
		subject_user_link = "?Profile/#{activity.subject.hub}/#{activity.subject.auth_address}/#{activity.subject.cert_user_id}"
		if activity.type == "post_like"
			body = [
				h("a", {href: activity_user_link, onclick: @Page.handleLinkClick}, activity.user_name), " liked ",
				h("a", {href: subject_user_link, onclick: @Page.handleLinkClick}, activity.subject.user_name), "'s ",
				h("a", {href: subject_user_link, onclick: @Page.handleLinkClick}, "post")
			]
		else if activity.type == "comment"
			body = [
				h("a", {href: activity_user_link, onclick: @Page.handleLinkClick}, activity.user_name), " commented on ",
				h("a", {href: subject_user_link, onclick: @Page.handleLinkClick}, activity.subject.user_name), "'s ",
				h("a", {href: subject_user_link, onclick: @Page.handleLinkClick}, "post"), ": #{activity.body}"
			]
		else if activity.type == "follow"
			body = [
				h("a", {href: activity_user_link, onclick: @Page.handleLinkClick}, activity.user_name), " started following ",
				h("a", {href: subject_user_link, onclick: @Page.handleLinkClick}, activity.subject.user_name)
			]
		else
			body = activity.body
		h("div.activity", {key: "#{activity.cert_user_id}_#{activity.date_added}", title: Time.since(activity.date_added), enterAnimation: Animation.slideDown, exitAnimation: Animation.slideUp}, [
			h("div.circle"),
			h("div.body", body)
		])

	render: =>
		if @need_update then @update()
		if @activities == null # Not loaded yet
			return null

		h("div.activity-list", [
			if @activities.length > 0
				h("h2", {enterAnimation: Animation.slideDown, exitAnimation: Animation.slideUp}, "Activity feed")
			h("div.items", [
				h("div.bg-line"),
				@activities[0..@limit-1].map(@renderActivity)
			]),
			if @activities.length > @limit
				h("a.more.small", {href: "#More", onclick: @handleMoreClick, enterAnimation: Animation.slideDown, exitAnimation: Animation.slideUp}, "Show more...")
			# if @loading
			# 	h("span.more.small", {enterAnimation: Animation.slideDown, exitAnimation: Animation.slideUp}, "Loading...", )

		])

window.ActivityList = ActivityList
