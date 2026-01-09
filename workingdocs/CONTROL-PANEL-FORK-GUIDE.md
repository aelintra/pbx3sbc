# OpenSIPS Control Panel Fork & Patch Guide

## Overview

Instead of patching the control panel after installation, we fork the repository and apply all fixes once. This makes the installer cleaner and ensures consistent patches.

**Fork Repository:** https://github.com/OpenSIPS/opensips-cp (fork to your GitHub account)

**Base Version:** 9.3.5 (tag: `9.3.5`)

## Required Patches

All patches are applied to the `9.3.5` tag/branch.

### 1. Domain Tool PHP Fix (`web/tools/system/domains/domains.php`)

**Issue:** Code attempts INSERT on GET requests (causes 500 error)

**Fix:** Wrap INSERT logic in POST request check

**Location:** Around line 46-67 in the `if ($action=="add")` block

**Change:**
```php
if ($action=="add")
{
    # Only process INSERT if this is a POST request (form submission)
    if ($_SERVER['REQUEST_METHOD'] == 'POST' && isset($_POST['add']))
    {
        $domain=$_POST['domain'];
        $sql = "INSERT INTO ".$table." (domain, setid" .($has_attrs?",attrs":""). ", last_modified) VALUES (?, ?".($has_attrs?", ?":"").", NOW())";
        $stm = $link->prepare($sql);
        if ($stm === false) {
            die('Failed to issue query ['.$sql.'], error message : ' . print_r($link->errorInfo(), true));
        }
        $setid = isset($_POST['setid']) && $_POST['setid'] != '' ? intval($_POST['setid']) : 0;
        $vals = array($domain, $setid);
        if ($has_attrs)
            $vals[] = $_POST['attrs'];
        if ($stm->execute($vals)==FALSE) {
            $errors = "Add/Insert to DB failed with: ". print_r($stm->errorInfo(), true);
        } else {
            $info="Domain Name has been inserted";
            // If setid was 0, update it to match the auto-generated id
            if ($setid == 0) {
                $last_id = $link->lastInsertId();
                $update_sql = "UPDATE ".$table." SET setid = id WHERE id = ? AND setid = 0";
                $update_stm = $link->prepare($update_sql);
                if ($update_stm) {
                    $update_stm->execute(array($last_id));
                }
            }
        }
    }
    # If GET request, just display the form (handled by template)
}
```

**Also update the `if ($action=="save")` block** to include setid in UPDATE:

```php
if ($action=="save")
{
    $domain=$_POST['domain'];
    $setid = isset($_POST['setid']) && $_POST['setid'] != '' ? intval($_POST['setid']) : 0;
    $sql = "UPDATE ".$table." SET domain=?, setid=?".($has_attrs?", attrs=?":""). ", last_modified=NOW() WHERE id=?";
    // ... rest of UPDATE logic
}
```

### 2. Domain Tool Form Template (`web/tools/system/domains/template/domains.form.php`)

**Issue:** Missing setid field in add/edit form

**Fix:** Add setid input field after domain field

**Location:** After the domain field input

**Change:**
```php
form_generate_input_text("SIP Domain", "A SIP Domain to be considered local by OpenSIPS - can be an IP or a FQDN",
    "domain", "n", $domain_form['domain'], 128, "^(([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})|(([A-Za-z0-9-]+\.)+[a-zA-Z]+))$");
form_generate_input_text("Set ID", "Dispatcher Set ID for routing to backend servers",
    "setid", "n", isset($domain_form['setid']) ? $domain_form['setid'] : '', 10, "^[0-9]+$");
if ($has_attrs) {
    form_generate_input_text("Attributes", "Attributes assigned to the domain",
        "attrs", "y", $domain_form['attrs'], 128, get_settings_value("attributes_regex"));
}
```

**Also ensure the SELECT query in domains.php includes setid** (in the edit action block):
```php
$sql = "SELECT * FROM ".$table." WHERE id=?";
// Should already work, but verify setid is in the result
```

### 3. Domain Tool Main Template (`web/tools/system/domains/template/domains.main.php`)

**Issue:** Missing ID and Set ID columns in domain list, disabled submit button, missing JavaScript initialization

**Fix:** Multiple changes:

#### 3a. Remove `disabled=true` from submit button

**Location:** Find submit button with `disabled=true` attribute, remove it

#### 3b. Add ID and Set ID columns to table header

**Location:** In the `<table>` header section

**Change:**
```php
<tr>
    <th align="center" class="listTitle">ID</th>
    <th align="center" class="listTitle">Domain Name</th>
    <th align="center" class="listTitle">Set ID</th>
<?php if ($has_attrs) { ?>
    <th align="center" class="listTitle">Attributes</th>
<?php } ?>
    <th align="center" class="listTitle">Last Modified</th>
    <th align="center" class="listTitle">Edit</th>
    <th align="center" class="listTitle">Delete</th>
</tr>
```

#### 3c. Add ID and Set ID columns to table rows

**Location:** In the table row loop

**Change:**
```php
<tr>
    <td class="<?=$row_style?>"><?=$row['id']?></td>
    <td class="<?=$row_style?>"><?=$row['domain']?></td>
    <td class="<?=$row_style?>"><?=$row['setid']?></td>
<?php if ($has_attrs) { ?>
    <td class="<?=$row_style?>"><?=$row['attrs']?></td>
<?php } ?>
    <td class="<?=$row_style?>"><?=$row['last_modified']?></td>
    <td class="<?=$row_style."Img"?>" align="center"><?=$edit_link?></td>
    <td class="<?=$row_style."Img"?>" align="center"><?=$delete_link?></td>
</tr>
```

**Also update colspan** in the "no results" row:
```php
if ($data_no==0) echo('<tr><td class="rowEven" colspan="'.($has_attrs?7:6).'" align="center"><br>'.$no_result.'<br><br></td></tr>');
```

#### 3d. Add JavaScript initialization

**Location:** After `</table>` tag, before `</form>` tag

**Change:**
```html
<script>
form_init_status();
</script>

<script>
(function() {
  var domainField = document.getElementById("domain");
  if (domainField) {
    domainField.addEventListener("input", function() {
      validate_input("domain", "domain_ok", "^(([0-9]{1,3}\\.){3}[0-9]{1,3})|(([A-Za-z0-9-]+\\.)+[a-zA-Z]+)$", null, "");
    });
  }
})();
</script>
```

## Fork Workflow

1. **Fork the repository:**
   - Go to https://github.com/OpenSIPS/opensips-cp
   - Click "Fork" to create your own fork
   - Note the fork URL (e.g., `https://github.com/YOUR_USERNAME/opensips-cp`)

2. **Clone your fork:**
   ```bash
   git clone https://github.com/YOUR_USERNAME/opensips-cp.git
   cd opensips-cp
   ```

3. **Create a branch from the 9.3.5 tag:**
   ```bash
   git checkout -b pbx3sbc-patches 9.3.5
   ```

4. **Apply all patches** to the files listed above

5. **Commit changes:**
   ```bash
   git add web/tools/system/domains/
   git commit -m "Apply domain tool fixes: setid support, POST check, JavaScript fixes"
   ```

6. **Create a release/tag:**
   ```bash
   git tag -a v9.3.5-pbx3sbc -m "OpenSIPS Control Panel 9.3.5 with pbx3sbc patches"
   git push origin pbx3sbc-patches
   git push origin v9.3.5-pbx3sbc
   ```

7. **Update installer** to use your fork URL

## Installer Integration

The installer will download from your fork instead of upstream:

```bash
# In install-control-panel.sh, update DOWNLOAD_URL:
FORK_REPO="YOUR_USERNAME/opensips-cp"  # or full GitHub URL
DOWNLOAD_URL="https://github.com/${FORK_REPO}/archive/refs/tags/v9.3.5-pbx3sbc.zip"
```

Or use the branch directly:
```bash
DOWNLOAD_URL="https://github.com/${FORK_REPO}/archive/refs/heads/pbx3sbc-patches.zip"
```

## Benefits

1. **Clean installer** - No complex patching logic
2. **Consistent patches** - All fixes applied once
3. **Version control** - Changes tracked in git
4. **Easier maintenance** - Update fork when needed
5. **Documented changes** - Clear commit history
6. **Temporary solution** - Fine since we're building our own panel anyway

## Notes

- This is a temporary solution until the custom admin panel is built
- All changes are backward compatible (setid defaults to id if not set)
- Fork can be deleted once custom panel is ready
- Consider contributing fixes upstream (though they may not accept setid changes)

