#!/usr/bin/env bash
# Fetch every comment surface on a PR as one JSON document.
# Usage: fetch-threads.sh <owner/repo> <pr-number>
set -euo pipefail

REPO="${1:?usage: fetch-threads.sh <owner/repo> <pr-number>}"
NUM="${2:?usage: fetch-threads.sh <owner/repo> <pr-number>}"
OWNER="${REPO%%/*}"
NAME="${REPO##*/}"

gh api graphql -f owner="$OWNER" -f name="$NAME" -F num="$NUM" -f query='
query($owner:String!, $name:String!, $num:Int!) {
  repository(owner:$owner, name:$name) {
    pullRequest(number:$num) {
      title
      url
      author { login }
      headRefName
      baseRefName
      reviewThreads(first:100) {
        nodes {
          id
          isResolved
          isOutdated
          path
          line
          originalLine
          comments(first:50) {
            nodes { databaseId author { login } body url createdAt }
          }
        }
      }
      reviews(first:50) {
        nodes { author { login } body state url submittedAt }
      }
      comments(first:100) {
        nodes { databaseId author { login } body url createdAt }
      }
    }
  }
}' --jq '
.data.repository.pullRequest as $pr | {
  title: $pr.title,
  url: $pr.url,
  author: $pr.author.login,
  head: $pr.headRefName,
  base: $pr.baseRefName,
  threads: [ $pr.reviewThreads.nodes[] | {
      kind: "inline",
      id: (.comments.nodes[0].databaseId | tostring),
      resolved: .isResolved,
      outdated: .isOutdated,
      where: (.path + ":" + ((.line // .originalLine) | tostring)),
      url: .comments.nodes[0].url,
      opener: .comments.nodes[0].author.login,
      comment: .comments.nodes[0].body,
      replies: [ .comments.nodes[1:][] | {author: .author.login, body: .body} ],
      last_author: (.comments.nodes[-1].author.login)
  } ],
  reviews: [ $pr.reviews.nodes[] | select(.body != "") | {
      kind: "review",
      id: ("review-" + (.submittedAt | tostring)),
      resolved: false, outdated: false,
      where: ("review summary (" + .state + ")"),
      url: .url, opener: .author.login, comment: .body,
      replies: [], last_author: .author.login
  } ],
  conversation: [ $pr.comments.nodes[] | {
      kind: "conversation",
      id: (.databaseId | tostring),
      resolved: false, outdated: false,
      where: "conversation",
      url: .url, opener: .author.login, comment: .body,
      replies: [], last_author: .author.login
  } ]
}'
