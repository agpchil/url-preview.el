# url-preview.el

Preview urls in buffers.

This package tries to provide a generic way to preview urls. The main goal was to give a common framework to packages like [erc-image.el](https://github.com/kidd/erc-image.el), [erc-youtube.el](https://github.com/kidd/erc-youtube.el) and [erc-tweet.el](https://github.com/kidd/erc-tweet.el).

## Requirements

This package requires [dash.el](https://github.com/magnars/dash.el).

You probably want to install some `url-preview` predefined modules too.

## Install
(todo)

## Usage

```lisp
(require 'url-preview)
(require 'url-preview-image)
(url-preview-module-enable "image")
```

### Interactive

Call `(url-preview)` to preview the url under the cursor, region or line.

### ERC

You need to subscribe `url-preview-handler` to hooks `erc-insert-modify-hook` and
`erc-send-modify-hook`.

```lisp
(add-hook 'erc-insert-modify-hook 'url-preview-handler t)
(add-hook 'erc-send-modify-hook 'url-preview-handler t)
```

### Weechat

You need to subscribe `url-preview-handler` to hook `weechat-insert-modify-hook`.

```lisp
(add-hook 'weechat-insert-modify-hook 'url-preview-handler)
```

## Customize

`M-x customize-group url-preview RET`

## Module
(todo)

## Cache
(todo)
