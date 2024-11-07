let s:cpo_save = &cpo
set cpo&vim
let s:not_supported = -1
let s:github_value = 1
let s:gitlab_value = 2
let s:bitbucket_value = 3
let s:git_site_enum = { 'github': s:github_value, 'gitlab': s:gitlab_value, 'bitbucket': s:bitbucket_value }

if !exists('g:vim_git_browse_target_branch')
  let g:vim_git_browse_target_branch = 'master'
endif

if !exists('g:vim_git_browse_open_url_browser_default')
  let g:vim_git_browse_open_url_browser_default = 'xdg-open'
endif

function! s:OpenUrl(url) abort
  let l:url = escape(a:url, "%|*#")
  if has('win16') || has('win32') || has('win64')
    exe '!start cmd /cstart /b ' . l:url . ''
  elseif has('mac') || has('macunix') || has('gui_macvim')
    exe 'silent !open "'. l:url . '"'
  else
    exe 'silent! !' . g:vim_git_browse_open_url_browser_default . ' "' . l:url . '" &> /dev/null &'
  endif
endfunction

function! s:CallGitCommand(command) abort
  let l:git_command_result = system(a:command)
  if l:git_command_result =~ '\fatal:'
    return v:null
  endif

  return l:git_command_result
endfunction

function! s:GetGitRemoteUrl()
  let l:git_remote_url = s:CallGitCommand('git remote get-url origin | tr -d "\n"')
  return system('echo ' . l:git_remote_url . ' | sed -Ee ''s#(git@|git://)#https://#'' -e ''s@com:@com/@'' -e ''s%\.git$%%'' -e ''s#(https://.*bitbucket)#https://bitbucket#'' -e ''s#(bitbucket.org:)#bitbucket.org/#'' | tr -d "\n"')
endfunction

function! s:GetGitRootPath() abort
  return s:CallGitCommand('git rev-parse --show-toplevel | tr -d "\n"')
endfunction

function! s:GetCurrentBranchName() abort
  return s:CallGitCommand('git rev-parse --abbrev-ref HEAD | tr -d "\n"')
endfunction

function! s:ShouldOpenGitFile() abort
  return !empty(expand('%:h'))
endfunction

function! s:GetRelativePath(git_root_path) abort
  let l:absolute_path = expand('%:p')
  return substitute(l:absolute_path, a:git_root_path . '/', '', '')
endfunction

function! s:GetLatestCommitHashRemote(branch_name) abort
  let l:origin_branch_name = 'origin/' . a:branch_name

  return s:CallGitCommand('git rev-parse ' . l:origin_branch_name . ' | tr -d "\n"')
endfunction

function! s:GetGithubPullRequestUrl(git_remote_url, commit_hash) abort
  let l:pull_request = s:CallGitCommand('git ls-remote origin "refs/pull/*/head" | grep ' . a:commit_hash . ' | tr -d "\n"')
  if empty(l:pull_request)
    return v:null
  endif

  let l:pull_request_id = system('echo ' . l:pull_request . ' | awk -F''/'' ''{print $3}'' | tr -d "\n"')
  let l:git_remote_url = a:git_remote_url

  let l:pull_request_url = l:git_remote_url . '/pull/' . l:pull_request_id

  return l:pull_request_url
endfunction

function! s:GetGitLabMergeRequestUrl(git_remote_url, commit_hash) abort
  let l:merge_request = s:CallGitCommand('git ls-remote origin "*/merge-requests/*/head" | grep ' . a:commit_hash . ' | tr -d "\n"')
  if empty(l:merge_request)
    return v:null
  endif

  let l:merge_request_id = system('echo ' . l:merge_request . ' | awk -F''/'' ''{print $3}'' | tr -d "\n"')
  let l:git_remote_url = a:git_remote_url

  let l:merge_request_url = l:git_remote_url . '/-/merge_requests/' . l:merge_request_id

  return l:merge_request_url
endfunction

function! s:OpenGitRootInBrowser(git_remote_url, branch_name) abort
  let l:git_site_type = s:GetGitSiteType(a:git_remote_url)

  if l:git_site_type == s:gitlab_value || l:git_site_type == s:github_value
    let l:git_url = a:git_remote_url . '/tree/' . a:branch_name
    call s:OpenUrl(l:git_url)
    return
  elseif l:git_site_type == s:bitbucket_value
    let l:git_url = a:git_remote_url . '/src/' . a:branch_name . '/'
    call s:OpenUrl(l:git_url)
    return
  else
    echo '[vim-git-browse] Git site not supported'
    return
  endif
endfunction

function! s:GetGitUrlWithLine(git_url, line1, line2, git_site_type)
  let l:git_url = a:git_url
  if a:git_site_type == s:gitlab_value || a:git_site_type == s:github_value
    let l:git_url .= '#L' . a:line1
  elseif a:git_site_type == s:bitbucket_value
    let l:git_url .= '#-' . a:line1
  endif
  if a:line1 == a:line2
    return l:git_url
  endif

  if a:git_site_type == s:github_value
    let l:git_url .= '-L' . a:line2
  elseif a:git_site_type == s:gitlab_value
    let l:git_url .= '-' . a:line2
  elseif a:git_site_type == s:bitbucket_value
    let l:git_url .= ',' . a:line2
  endif

  return l:git_url
endfunction

function! s:OpenGitFileInBrowser(git_remote_url, branch_name, relative_path, visual_mode) abort
  let l:git_site_type = s:GetGitSiteType(a:git_remote_url)

  let l:git_url = a:git_remote_url
  if l:git_site_type == s:gitlab_value || l:git_site_type == s:github_value
    let l:git_url = l:git_url . '/blob/' . a:branch_name . '/' . a:relative_path
  elseif l:git_site_type == s:bitbucket_value
    let l:git_url = l:git_url . '/src/' . a:branch_name . '/' . a:relative_path
  else
    echo '[vim-git-browse] Git site not supported'
    return
  endif

  if a:visual_mode
    let l:first_line = getpos("'<")[1]
    let l:last_line = getpos("'>")[1]
    let l:git_url = s:GetGitUrlWithLine(l:git_url, l:first_line, l:last_line, l:git_site_type)

    call s:OpenUrl(l:git_url)
  else

    call s:OpenUrl(l:git_url)
  endif
endfunction

function! s:OpenGitRepositoryInBrowser(visual_mode, git_remote_url, branch_name, git_root_path) abort
  if s:ShouldOpenGitFile() == v:false
    call s:OpenGitRootInBrowser(a:git_remote_url, a:branch_name)
    return
  endif

  let l:relative_path = s:GetRelativePath(a:git_root_path)
  call s:OpenGitFileInBrowser(a:git_remote_url, a:branch_name, l:relative_path, a:visual_mode)
endfunction

function! s:GetGitSiteType(git_remote_url) abort
  for git_site in keys(s:git_site_enum)
    if stridx(a:git_remote_url, git_site) != -1
      return s:git_site_enum[git_site]
    endif
  endfor

  return s:not_supported
endfunction

function! vim_git_browse#GitBrowse(visual_mode, ...) abort
  echo '[vim-git-browse] Opening git...'
  let l:git_root_path = s:GetGitRootPath()
  if l:git_root_path is v:null
    echo '[vim-git-browse] Please use in git project'
    return
  endif

  let l:git_remote_url = s:GetGitRemoteUrl()
  let l:branch_name = get(a:, 1, s:GetCurrentBranchName())

  call s:OpenGitRepositoryInBrowser(a:visual_mode, l:git_remote_url, l:branch_name, l:git_root_path)
endfunction

function! vim_git_browse#GitPullRequest() abort
  echo '[vim-git-browse] Opening pull request...'
  let l:git_root_path = s:GetGitRootPath()
  if l:git_root_path is v:null
    echo '[vim-git-browse] Please use in git project'
    return 0
  endif

  let l:branch_name = s:GetCurrentBranchName()
  let l:latest_commit_hash = s:GetLatestCommitHashRemote(l:branch_name)
  if l:latest_commit_hash is v:null
    echo '[vim-git-browse] Could not find remote branch ' . l:branch_name
    return 0
  endif
  let l:git_remote_url = s:GetGitRemoteUrl()
  let l:merge_request_url = v:null
  let l:git_site_type = s:GetGitSiteType(l:git_remote_url)

  if l:git_site_type == s:gitlab_value
    let l:merge_request_url = s:GetGitLabMergeRequestUrl(l:git_remote_url, l:latest_commit_hash)
  elseif l:git_site_type == s:github_value
    let l:merge_request_url = s:GetGithubPullRequestUrl(l:git_remote_url, l:latest_commit_hash)
  else
    echo '[vim-git-browse] Git site not supported'
    return 0
  endif

  if l:merge_request_url is v:null
    echo '[vim-git-browse] Could not find pull/merge request for branch ' . l:branch_name
    return 0
  endif

  call s:OpenUrl(l:merge_request_url)
  return 1
endfunction

function! vim_git_browse#GitCreatePullRequest() abort
  echo '[vim-git-browse] Creating pull request...'
  let l:git_root_path = s:GetGitRootPath()
  if l:git_root_path is v:null
    echo '[vim-git-browse] Please use in git project'
    return 0
  endif

  let l:branch_name = s:GetCurrentBranchName()
  if l:branch_name == g:vim_git_browse_target_branch
    echo '[vim-git-browse] Source branch can not be the same as target branch'
    return 0
  endif

  let l:git_remote_url = s:GetGitRemoteUrl()
  let l:create_merge_request_url = v:null
  let l:git_site_type = s:GetGitSiteType(l:git_remote_url)

  if l:git_site_type == s:gitlab_value
    let l:create_merge_request_url = l:git_remote_url . '/merge_requests/new?utf8=%E2%9C%93&merge_request[source_branch]=' . l:branch_name . '&merge_request[target_branch]=' . g:vim_git_browse_target_branch
  elseif l:git_site_type == s:github_value
    let l:create_merge_request_url = l:git_remote_url . '/compare/' . g:vim_git_browse_target_branch . '...' . l:branch_name
  else
    echo '[vim-git-browse] Git site not supported'
    return 0
  endif

  call s:OpenUrl(l:create_merge_request_url)
  return 1
endfunction

function! vim_git_browse#GitOpenPullRequest() abort
  if !vim_git_browse#GitPullRequest()
    call vim_git_browse#GitCreatePullRequest()
  endif
endfunction

function! vim_git_browse#GitOpenPipelines() abort
  let l:git_remote_url = s:GetGitRemoteUrl()
  let l:git_site_type = s:GetGitSiteType(l:git_remote_url)
  let l:git_branch_name = s:GetCurrentBranchName()
  let l:latest_commit_hash = s:GetLatestCommitHashRemote(l:git_branch_name)

  let l:git_url = l:git_remote_url
  if l:git_site_type == s:gitlab_value
    let l:merge_request_url = s:GetGitLabMergeRequestUrl(l:git_remote_url, l:latest_commit_hash)
    let l:git_url = l:merge_request_url . '/pipelines'
  elseif l:git_site_type == s:github_value
    let l:git_url = l:git_url . '/actions?query=branch%3A' . l:git_branch_name
  else
    echo '[vim-git-browse] Git site not supported'
    return
  endif

  call s:OpenUrl(l:git_url)
endfunction

function! vim_git_browse#GitOpenRepo() abort
  call s:OpenUrl(s:GetGitRemoteUrl())
endfunction

let &cpo = s:cpo_save
unlet s:cpo_save
