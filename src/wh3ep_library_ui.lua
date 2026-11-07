local byte_sub=string.sub_lua or string.sub
-- Library UI. The model/storage are real modules; only native UI and capture are boundaries.
return function(model,storage,adapter,localization)
    localization=localization or wh3ep_localization_factory({ru=wh3ep_locale_ru,eng=wh3ep_locale_eng,cn=wh3ep_locale_cn,zh=wh3ep_locale_zh,sp=wh3ep_locale_sp,br=wh3ep_locale_br,ge=wh3ep_locale_ge,ja=wh3ep_locale_ja,fr=wh3ep_locale_fr,pl=wh3ep_locale_pl,kr=wh3ep_locale_kr},common and common.get_context_value)
    local L=localization.text
    local native_text=true -- Every active UI caption is supplied by the selected catalog.
    local U={}
    local selected_cqi,current,library,library_status,metadata
    local entry,frame,popup,draft
    local popup_locked,popup_topmost,popup_lock_owner=false,false,nil
    local controls,rows,button_ids={},{},{}
    local label_sizes={}
    local text_insets={}
    local function checked_state(component,state)
        if component:SetState(state)==false then error('required_ui_state_missing',0)end
    end
    local function container_priority(component,value)
        -- Only initialize a new container; re-propagating on reuse flattens child layers.
        if component:Priority()~=value then component:PropagatePriority(value)end
    end
    local function button_inset(id)
        if id=='wh3ep_lib_open'then return 72 end
        if id=='wh3ep_lib_previous'or id=='wh3ep_lib_next'or id=='button_preview_previous'or id=='button_preview_next'then return 64 end
        return 48
    end
    local base_states,hovered_id={},nil
    local reporters={}
    local row_favorites={}
    local reference_logged={}
    local visible=false
    local started,entry_panel_open=false,false
    local entry_generation=0
    local start_entry_tracking
    local save_scope='class'
    local display_state
    local function refresh_display()
        display_state=nil
        if adapter.inspect and selected_cqi then
            local ok,state=pcall(adapter.inspect,selected_cqi)
            if ok and type(state)=='table'then display_state=state end
        end
    end
    local take,apply_report=false,nil
    local function apply_busy()return adapter.apply and adapter.apply.busy()end
    local function panel_cqi()
        -- 8.1 passes the displayed character here; map CharacterSelected can lag portraits.
        local ok,cqi=pcall(function()
            local context=find_uicomponent(core:get_ui_root(),'character_details_panel','character_context_parent')
            if not context or not context:Visible(true)then return end
            local id=context:GetContextObjectId('CcoCampaignCharacter')
            if not id or id==''then return end
            return common.get_context_value('CcoCampaignCharacter',id,'CQI')
        end)
        if ok and type(cqi)=='number'and cqi>0 and cqi%1==0 then return cqi end
    end
    local selected_id,query,filter,page=nil,'','matching',1
    local library_pages=1
    local filters={'matching','general','all','favorites'}
    local filter_menu_open=false
    local filter_names={matching=L('filter_matching'),general=L('filter_general'),all=L('filter_all'),favorites=L('filter_favorites')}
    local preset_icons={}
    for _,key in ipairs(model.preset_icon_keys())do preset_icons[key]=true end
    local x,y,height,page_size=0,0,730,10
    local render,show_recovery_entry,render_apply_preview,open_popup,place_entry,fitted,paint_button,render_progress,refresh_form,set_icon
    local progress,progress_total
    local card_slots=12
    local library_help=L('help_library')
    local preview_help=L('help_preview')
    local result_help=L('help_result')
    local diagnostic_stage='event'
    local messages={invalid_name=L('error_invalid_name'),
        revision_conflict=L('error_library_changed'),content_conflict=L('error_library_changed'),
        future_schema=L('error_future_schema'),
        backup_available=L('error_backup_available'),
        preset_limit=L('error_preset_limit'),
        write_failed=L('error_write_failed'),
        write_failed_backup_available=L('error_write_backup'),
        stage_write_failed=L('error_stage_write'),
        wrong_turn=L('error_wrong_turn'),plan_changed=L('error_plan_changed'),
        inventory_too_large=L('error_inventory_large'),busy=L('error_busy'),
        engine_error=L('error_engine'),
        input_unavailable=L('error_input'),
        select_character=L('error_select_character'),multiplayer=L('error_multiplayer')}
    local function explain(code) return messages[code] or L('error_default') end
    local function text(component,value)
        if not component then return end
        if paint_button and paint_button(component,value)then return end
        component:SetText(value,'')
        local size=label_sizes[component:Id()]
        -- Fixed Never split metrics: SetText must not resize image-backed controls.
        if size then component:Resize(size[1],size[2],false)end
        local id=component:Id()
        if id=='wh3ep_lib_save_class'or id=='wh3ep_lib_change_scope'or id=='wh3ep_lib_status'or id=='preview_take_label'then
            -- Numeric-only native diagnostics. TextDimensions is used by stock lib_text_pointers.
            pcall(function()
                local tw,th=component:TextDimensions();local cw,ch=component:Dimensions()
                ModLog('[WH3EP] ui_text_geometry='..id..';component='..cw..'x'..ch..';text='..tw..'x'..th)
            end)
        end
    end
    local function entry_caption(caption,detail)
        if not entry then return end
        local label=find_uicomponent(entry,'button_txt')or entry
        text_insets[label:Id()]=72
        text(label,fitted(label,caption))
        entry:SetTooltipText(detail or caption,true)
    end
    local function status(value)text(controls.status,controls.status and fitted(controls.status,value)or value);if controls.status then controls.status:SetVisible(true);controls.status:SetTooltipText(value,true)end end
    local function release_popup_native()
        -- Only release locks acquired by this popup; never unlock a donor confirmation.
        if popup_locked then popup_lock_owner:UnLockPriority();popup_locked=false;popup_lock_owner=nil end
        if popup_topmost then if popup then popup:RemoveTopMost()end;popup_topmost=false end
    end
    local faulted=false
    local function guarded(callback)
        if faulted then return end
        diagnostic_stage='event'
        local ok,failure=pcall(callback)
        if not ok then
            faulted=true
            if adapter.apply then pcall(adapter.apply.cancel)end
            ModLog('[WH3EP] library_ui_lua_error')
            ModLog('[WH3EP] library_ui_error_stage='..diagnostic_stage)
            -- CA overrides string.find with a three-argument UTF8 implementation.
            -- Protect diagnostics independently and never emit raw exception text.
            local diagnosed=pcall(function()
                local message=type(failure)=='string' and failure or ''
                local find=string.find_lua or string.find
                local _,_,line=find(message,':(%d+):')
                local kind='unknown'
                for _,candidate in ipairs({'call','index','compare','concatenate','arithmetic'})do
                    if find(message,'attempt to '..candidate)then kind=candidate;break end
                end
                ModLog('[WH3EP] library_ui_error_line='..(line or 'unknown'))
                ModLog('[WH3EP] library_ui_error_kind='..kind)
            end)
            if not diagnosed then ModLog('[WH3EP] library_ui_diagnostic_failed')end
            -- Do not leave a partly rendered native panel accepting further clicks.
            visible=false;draft=nil
            pcall(release_popup_native)
            pcall(function()if popup then popup:SetVisible(false)end end)
            pcall(function()if frame then frame:SetVisible(false)end end)
            pcall(function()
                if adapter.apply and adapter.apply.waiting()then show_recovery_entry()
                else
                    local parent=find_uicomponent(core:get_ui_root(),'character_details_panel')
                    if parent and entry then place_entry(parent)end
                    entry_caption(L('button_error'),L('error_menu'))
                end
            end)
        end
    end
    local function report_events(component)
        local id=component:Id();if not reporters[id]then component:AddScriptEventReporter();reporters[id]=true end
    end
    -- A cheap fresh snapshot of major anchors, not clipped/scrolling descendants.
    local function entry_geometry(parent)
        local px,py=parent:Position();local pw,ph=parent:Dimensions()
        local equipment=find_uicomponent(parent,'character_context_parent','tab_panels','character_details_subpanel','equipment_holder')
        local signature={};local ready=parent:Visible(true)and pw>0 and ph>0
        local function sample(component,major)
            if not component then signature[#signature+1]='absent';return end
            local cx,cy=component:Position();local cw,ch=component:Dimensions();local shown=component:Visible(true)
            signature[#signature+1]=table.concat({cx,cy,cw,ch,tostring(shown)},',')
            -- Small native frame-edge overflow is allowed; animated offscreen columns are not.
            if major and shown and (cw<=0 or ch<=0 or cx<px-16 or cy<py-16 or cx+cw>px+pw+16 or cy+ch>py+ph+16)then ready=false end
        end
        sample(parent,false);sample(equipment,true)
        if equipment then
            if not equipment:Visible(true)then ready=false end
            sample(find_uicomponent(equipment,'ancillary_parent','magic_items_equiped'),true)
            sample(find_uicomponent(equipment,'ancillary_parent','general_ancillaries_equipped'),true)
            sample(find_uicomponent(equipment,'global_pool'),true)
        end
        return table.concat(signature,';'),ready
    end
    local function stop_entry_tracking()
        entry_generation=entry_generation+1
        cm:remove_real_callback('wh3ep_entry_layout')
    end
    start_entry_tracking=function()
        stop_entry_tracking()
        if not entry_panel_open then return end
        local generation,ticks,last=entry_generation,0,nil
        -- Six seconds per lifecycle event; late changes remain a native acceptance gate.
        cm:repeat_real_callback(function()
            if generation~=entry_generation or not entry_panel_open then return end
            ticks=ticks+1
            local ok=pcall(function()
                local parent=find_uicomponent(core:get_ui_root(),'character_details_panel')
                entry=parent and find_uicomponent(parent,'wh3ep_lib_open')or nil
                if not entry then return end
                if visible or draft or(faulted and not(adapter.apply and adapter.apply.waiting()))then entry:SetVisible(false);last=nil;return end
                local signature,ready=entry_geometry(parent)
                if not ready then entry:SetVisible(false)end
                if signature~=last then last=signature;place_entry(parent)end
            end)
            if not ok then
                pcall(function()local parent=find_uicomponent(core:get_ui_root(),'character_details_panel');local fresh=parent and find_uicomponent(parent,'wh3ep_lib_open');if fresh then fresh:SetVisible(false)end end)
                ModLog('[WH3EP] ui_entry_tracking_geometry_failed')
            end
            if not ok or ticks>=30 then stop_entry_tracking()end
        end,200,'wh3ep_entry_layout')
    end
    place_entry=function(parent)
        entry:SetVisible(false) -- Do not retain an unchecked old rectangle if native geometry fails.
        if visible or draft or(faulted and not(adapter.apply and adapter.apply.waiting()))then return end
        local _,ready=entry_geometry(parent)
        if not ready then ModLog('[WH3EP] ui_entry_layout_ready=false');return end
        local px,py=parent:Position();local pw,ph=parent:Dimensions()
        -- Exact 8.1 path also used by the stock prologue interventions (line 928).
        local equipment=find_uicomponent(parent,'character_context_parent','tab_panels','character_details_subpanel','equipment_holder')
        local ew,eh,gap=184,46,12
        local ex,ey,source
        if equipment then
            -- Bounds() is only a maximum size; it cannot locate negative-offset children.
            -- Union each visible descendant's own screen rectangle instead.
            local left,top,right,bottom,count=nil,nil,nil,nil,0
            local function include(component,clip_left,clip_top,clip_right,clip_bottom)
                if not component:Visible(true)then return end
                local cx,cy=component:Position();local cw,ch=component:Dimensions()
                local cr,cb=cx+cw,cy+ch
                if clip_left then cx=math.max(cx,clip_left);cy=math.max(cy,clip_top);cr=math.min(cr,clip_right);cb=math.min(cb,clip_bottom)end
                -- Stock8.1 list_clip has clipchildren=true; scrolled rows can still
                -- report Visible(true) outside it. Other protruding children count.
                if component:Id()=='list_clip'then
                    if cr<=cx or cb<=cy then return end
                    clip_left,clip_top,clip_right,clip_bottom=cx,cy,cr,cb
                end
                if cw>0 and ch>0 and cr>cx and cb>cy then
                    left=left and math.min(left,cx)or cx;top=top and math.min(top,cy)or cy
                    right=right and math.max(right,cr)or cr;bottom=bottom and math.max(bottom,cb)or cb
                    count=count+1
                end
                for index=0,component:ChildCount()-1 do
                    local child=component:Find(index);if child then include(UIComponent(child),clip_left,clip_top,clip_right,clip_bottom)end
                end
            end
            include(equipment)
            local function fits(cx,cy)
                return left and cx>=px+gap and cy>=py+gap and cx+ew<=px+pw-gap and cy+eh<=py+ph-gap
                    and (cx+ew<=left-gap or cx>=right+gap or cy+eh<=top-gap or cy>=bottom+gap)
            end
            if left then
                for _,position in ipairs({{left-ew-gap,top},{left,top-eh-gap},{right+gap,top},{left,bottom+gap}})do
                    if fits(position[1],position[2])then ex,ey=position[1],position[2];break end
                end
                ModLog('[WH3EP] ui_entry_union='..left..','..top..','..(right-left)..','..(bottom-top)..';nodes='..count)
            end
            local function diagnose(label,component)
                if not component then return end
                local cx,cy=component:Position();local cw,ch=component:Dimensions();local bw,bh=component:Bounds()
                ModLog('[WH3EP] ui_entry_rect='..label..';xywh='..cx..','..cy..','..cw..','..ch..';bounds_wh='..bw..','..bh..';visible='..tostring(component:Visible(true)))
            end
            diagnose('holder',equipment)
            diagnose('magic',find_uicomponent(equipment,'ancillary_parent','magic_items_equiped'))
            diagnose('followers',find_uicomponent(equipment,'ancillary_parent','general_ancillaries_equipped'))
            diagnose('reserve',find_uicomponent(equipment,'global_pool'))
            source='equipment_visible_union'
        else
            -- Installed XML: top-right equipment_holder width 642; details subpanel y=150.
            -- Only use this panel-relative fallback when the native anchor is absent.
            ex,ey=px+math.max(gap,pw-642-ew-gap),py+150
            if ex+ew>px+pw-gap or ey+eh>py+ph-gap then ex=nil end
            source='panel_fallback'
        end
        entry:SetVisible(ex~=nil)
        if ex then entry:MoveTo(ex,ey)end
        local actual_x,actual_y=entry:Position();local actual_w,actual_h=entry:Dimensions()
        ModLog('[WH3EP] ui_entry_panel='..px..','..py..','..pw..','..ph)
        ModLog('[WH3EP] ui_entry_actual='..actual_x..','..actual_y..','..actual_w..','..actual_h)
        ModLog('[WH3EP] ui_entry_placement='..source..';visible='..tostring(ex~=nil))
    end
    local function label(id,value,dx,dy,width,tall,parent,style)
        local component=core:get_or_create_component(id,'ui/templates/'..(style or 'wh3ep_label')..'.twui.xml',parent or frame)
        component:PropagatePriority(parent and 221 or 151)
        component:SetCanResizeWidth(true);component:SetCanResizeHeight(true);component:Resize(width,tall)
        component:MoveTo(x+dx,y+dy);component:SetVisible(true)
        if id:match('^row_')then report_events(component)end
        label_sizes[id]={width,tall};text(component,value)
        return component
    end
    local function button(id,value,dx,dy,width,secondary,style,parent)
        local radio_label=style=='wh3ep_radio_label'or style=='wh3ep_radio_general_label'
        local template=native_text and radio_label and 'wh3ep_radio_text'or style
        local component=core:get_or_create_component(id,'ui/templates/'..(template or (secondary and 'wh3ep_secondary'or 'wh3ep_primary'))..'.twui.xml',parent or frame)
        local tall=(style=='wh3ep_radio'or style=='wh3ep_star'or style=='wh3ep_radio_label'or style=='wh3ep_radio_general_label')and 40 or style=='wh3ep_help'and 38 or style=='wh3ep_filter'and 44 or 46
        local role_size=({wh3ep_lib_save={250,52},wh3ep_lib_apply={196,51},wh3ep_lib_close={142,51},wh3ep_lib_previous={168,38},wh3ep_lib_next={170,38}})[id]
        if role_size then width,tall=role_size[1],role_size[2]end
        component:PropagatePriority(151);component:Resize(width or 350,tall)
        component:MoveTo(x+dx,y+dy);component:SetVisible(true)
        report_events(component)
        button_ids[id]=true
        text_insets[id]=button_inset(id)
        label_sizes[id]={width or 350,tall}
        if radio_label then
            if native_text then
                for _,state in ipairs({'active','hover','down','down_off','inactive','selected','selected_hover','selected_down','selected_down_off'})do checked_state(component,state);text(component,value)end
                checked_state(component,'active')
            end
            component:SetTooltipText(value,true)
        else text(find_uicomponent(component,'button_txt')or component,value)end
        return component
    end
    local function set_base(component,state)
        if not component then return end
        local id=component:Id();base_states[id]=state
        checked_state(component,hovered_id==id and state~='inactive'and (state=='selected'and 'selected_hover'or 'hover')or state)
    end
    local function button_text(id,value)
        if id=='favorite'then return end
        if id=='save_class_label'or id=='save_general_label'then if native_text then text(controls[id],value)end;controls[id]:SetTooltipText(value,true);return end
        local component=find_uicomponent(controls[id],'button_txt')or controls[id]
        if id=='filter'then text(component,fitted(component,value,38));component:SetTooltipText(value,true)
        else text(component,value)end
    end
    local function apply_buttons()
        if not adapter.apply then return end
        button_text('apply',adapter.apply.waiting()and L('button_verify') or apply_busy()and L('button_verifying')or L('button_preview'))
        button_text('close',apply_busy()and L('button_stop')or L('button_close'))
        if adapter.apply.waiting()then controls.apply:SetTooltipText(L('hint_verify_transfer'),true)elseif apply_busy()then controls.apply:SetTooltipText(L('hint_verifying'),true)end
        if apply_busy()then controls.close:SetTooltipText(L('hint_stop'),true)end
        local busy=apply_busy()
        local writable=library_status=='ok'or library_status=='new'
        for _,id in ipairs({'save','save_class','save_general','save_class_label','save_general_label','rename','overwrite','scope','delete','favorite'})do
            local requires_selection=id=='rename'or id=='overwrite'or id=='scope'or id=='delete'or id=='favorite'
            local enabled=not busy and ((writable and(not requires_selection or selected_id~=nil))or(id=='delete'and library_status=='backup_available'))
            local selected=((id=='save_class'or id=='save_class_label')and save_scope=='class')or((id=='save_general'or id=='save_general_label')and save_scope=='general')or(id=='favorite'and controls.favorite_selected)
            set_base(controls[id],not enabled and 'inactive'or selected and 'selected'or 'active')
        end
        for _,id in ipairs({'search','clear','filter'})do set_base(controls[id],busy and 'inactive'or 'active')end
        set_base(controls.previous,(busy or page<=1)and 'inactive'or 'active')
        set_base(controls.next,(busy or page>=library_pages)and 'inactive'or 'active')
        set_icon(controls.previous_arrow,'ui/skins/wh3ep/glyph_arrow_back'..((busy or page<=1)and '_inactive'or '')..'.png',34,height-140,18)
        set_icon(controls.next_arrow,'ui/skins/wh3ep/glyph_arrow_forward'..((busy or page>=library_pages)and '_inactive'or '')..'.png',452,height-140,18)
        controls.previous_arrow:SetVisible(library_pages>1);controls.next_arrow:SetVisible(library_pages>1)
        set_base(controls.apply,((busy and not adapter.apply.waiting())or(not busy and not selected_id))and 'inactive'or 'active')
        set_base(controls.close,'active')
        for index,selected in pairs(row_favorites)do set_base(find_uicomponent(frame,'row_star_'..index),(busy or not writable)and 'inactive'or selected and 'selected'or 'active')end
    end
    local terminal_reasons={not_applied=L('terminal_not_applied'),inventory_changed=L('terminal_inventory_changed'),error=L('terminal_error')}
    local function report_text(r)
        if terminal_reasons[r.status]then return L('result_confirmed_prefix')..(r.completed or 0)..L('result_stopped_suffix') end
        local sum=r.summary or{};local skipped=0
        for code,n in pairs(sum)do if code~='free'and code~='donor'and code~='already'then skipped=skipped+n end end
        return L('result_equipped_prefix')..(r.completed or 0)..L('result_already_separator')..(sum.already or 0)..L('result_skipped_separator')..skipped..L('result_missing_line')..(sum.missing or 0)..L('result_incompatible_separator')..(sum.incompatible or 0)..L('result_occupied_line')..(sum.occupied or 0)..L('result_no_slot_separator')..(sum.no_slot or 0)..L('result_unsupported_line')..(sum.unsupported or 0)
    end
    local function on_apply_update(report)
        apply_report=report
        ModLog('[WH3EP] apply_status='..tostring(report.status)..' completed='..tostring(report.completed))
        if not visible or not frame or(draft and draft.action~='result')or(not frame:Visible(true)and not(draft and draft.action=='result'))then return end
        guarded(function()
            apply_buttons()
            if render_progress then render_progress(report)end
            local summaries={running=L('progress_verifying'),awaiting_confirmation=L('progress_confirmation'),
                cancelled=L('progress_cancelled'),not_applied=L('progress_not_applied'),
                inventory_changed=L('progress_inventory_changed'),error=L('progress_error')}
            if report.status=='complete'or terminal_reasons[report.status]then
                refresh_display();status(report_text(report))
                open_popup('result',terminal_reasons[report.status]and L('result_stopped')or L('result_applied'),'',{report=report});controls.status:SetVisible(false)
            elseif report.code=='queue_cancelled_pending'then status(L('progress_pending'))
            else status(summaries[report.status]or L('progress_stopped'))end
        end)
    end
    show_recovery_entry=function()
        local parent=find_uicomponent(core:get_ui_root(),'character_details_panel')
        if not parent then return end
        entry=core:get_or_create_component('wh3ep_lib_open','ui/templates/wh3ep_entry.twui.xml',parent)
        entry:PropagatePriority(151);entry:Resize(184,46);label_sizes[entry:Id()]={184,46};report_events(entry);place_entry(parent)
        entry_caption(L('button_verify'),L('hint_verify_previous'))
        start_entry_tracking()
    end
    local function faulted_verification(context)
        if not adapter.apply or not adapter.apply.waiting()then return end
        local ok=pcall(function()
            local component=UIComponent(context.component)
            if component:Id()~='wh3ep_lib_open'and not uicomponent_descended_from(component,'wh3ep_lib_open')then return end
            -- Cancellation is mandatory: this recovery path may only read/verify.
            adapter.apply.cancel();adapter.apply.resume()
            local report=adapter.apply.report()
            if report and report.status=='cancelled'then entry_caption(L('button_verified'),L('hint_restart'))
            else entry_caption(L('button_see_log'),L('hint_check_stopped'))end
            ModLog('[WH3EP] apply_fault_recovery_checked')
        end)
        if not ok then ModLog('[WH3EP] apply_fault_recovery_error')end
    end
    local function close_popup()
        if cm and cm.remove_real_callback then cm:remove_real_callback('wh3ep_library_form')end
        draft=nil;hovered_id=nil
        release_popup_native()
        if popup then popup:SetVisible(false)end
        if frame then frame:SetVisible(visible and not faulted)end
        if entry and not faulted then
            if visible then entry:SetVisible(false)else
                local parent=find_uicomponent(core:get_ui_root(),'character_details_panel')
                if parent then place_entry(parent)end
            end
        end
    end
    local function close_filter_menu()
        if filter_menu_open and controls.filter_menu then controls.filter_menu:RemoveTopMost()end
        filter_menu_open=false
        if controls.filter_menu then controls.filter_menu:SetVisible(false)end
        for _,key in ipairs(filters)do
            local option=controls['filter_option_'..key]
            if option then option:SetVisible(false)end
        end
    end
    local function close()
        close_filter_menu()
        if adapter.apply then adapter.apply.cancel()end
        if progress then progress:SetVisible(false)end
        visible=false;close_popup()
        if cm and cm.remove_real_callback then cm:remove_real_callback('wh3ep_library_search')end
        if frame then frame:SetVisible(false)end
    end
    local function reload()
        library,library_status,metadata=storage.load()
        metadata=metadata or {}
    end
    local function writable()
        if library and (library_status=='ok' or library_status=='new')then return true end
        status(explain(library_status));return false
    end
    local function chosen()
        local entry_data=library and current and library.factions[current.faction_key]
        for _,preset in ipairs(entry_data and entry_data.presets or {})do if preset.id==selected_id then return preset end end
    end
    local function commit(updated,message,id)
        ModLog('[WH3EP] library_save_begin')
        diagnostic_stage='storage_save'
        local saved,code,info=storage.save(updated,library.library_revision,metadata.token)
        if not saved then reload();render();status(explain(code));ModLog('[WH3EP] library_save_failed='..tostring(code));return false end
        library,library_status,metadata=updated,'ok',info
        if id then selected_id=id end
        render();status(message)
        ModLog('[WH3EP] library_saved_revision='..tostring(library.library_revision))
        return true
    end
    local function clipped(value,limit)
        value=tostring(value):gsub('[%c]',' ')
        local offset,count=1,0
        while offset<=#value do
            local byte=value:byte(offset);local size=byte<128 and 1 or byte<224 and 2 or byte<240 and 3 or 4
            if count==limit then return byte_sub(value,1,offset-1)..'...'end
            count=count+1;offset=offset+size
        end
        return value
    end
    fitted=function(component,value,inset)
        value=tostring(value):gsub('[%c]',' ')
        local width=(label_sizes[component:Id()]or{250})[1]
        local limit=width-(text_insets[component:Id()]or inset or 8)
        local ok,width=pcall(function()return component:WidthOfTextLine(value)end)
        if not ok or type(width)~='number'or width<=0 then return clipped(value,18)end
        if width<=limit then return value end
        local ends={0};local offset=1
        while offset<=#value do local b=value:byte(offset);offset=offset+(b<128 and 1 or b<224 and 2 or b<240 and 3 or 4);ends[#ends+1]=offset-1 end
        local low,high=1,#ends
        while low<high do
            local mid=math.ceil((low+high)/2);local candidate=byte_sub(value,1,ends[mid])..'…'
            local measured=component:WidthOfTextLine(candidate)
            if measured<=limit then low=mid else high=mid-1 end
        end
        return byte_sub(value,1,ends[low])..'…'
    end
    local function prefix(value,maximum)
        local offset,count=1,0
        while offset<=#value and count<maximum do local b=value:byte(offset);offset=offset+(b<128 and 1 or b<224 and 2 or b<240 and 3 or 4);count=count+1 end
        return byte_sub(value,1,offset-1),count
    end
    refresh_form=function()
        if not draft or(draft.action~='create'and draft.action~='rename')or not popup then return end
        local input=find_uicomponent(popup,'text_input');if not input then return end
        local value=input:GetStateText();if type(value)~='string'then return end
        local limited,count=prefix(value,30)
        if limited~=value then text(input,limited)end
        local counter=find_uicomponent(popup,'form_counter');if counter then text(counter,count..' / 30')end
    end
    local paint_cache={}
    local paint_roles={wh3ep_lib_save={'save',L('button_save')},wh3ep_lib_apply={'preview',L('button_preview')},wh3ep_lib_close={'close',L('button_close')},wh3ep_lib_rename={'rename',L('button_rename')},wh3ep_lib_overwrite={'update',L('button_update')},wh3ep_lib_change_scope={'scope',L('button_general')},wh3ep_lib_delete={'delete',L('button_delete')},wh3ep_lib_previous={'previous',L('button_previous')},wh3ep_lib_next={'next',L('button_next')},wh3ep_lib_help={'library_help','?'},button_ok={'apply',L('button_apply')},button_cancel={'cancel',L('button_cancel')},button_preview_previous={'previous',L('button_previous')},button_preview_next={'next',L('button_next')},button_preview_help={'help','?'},button_preview_close={'cross','×'}}
    paint_button=function(component,value)
        local id=component:Id();local role=paint_roles[id]
        if id=='button_ok'and draft and draft.action=='delete'then role={'delete_confirm',L('button_delete')}end
        if id:match('^wh3ep_lib_filter_option_')then role={'dropdown',value}end
        if not role then return false end
        local size=label_sizes[id];if not size then return false end
        value=tostring(value);local glyph=id=='wh3ep_lib_help'or id=='button_preview_help'or id=='button_preview_close'
        local mode=glyph and 'fixed'or 'plain'
        local key=role[1]..'/'..mode..'/'..value..'/'..size[1]..'x'..size[2]..'/'..(role[1]=='dropdown'and filter or '')
        if paint_cache[id]~=key then
            local current_state=component:CurrentState()
            local layers={'active','hover','down','inactive'}
            for _,state in ipairs({'active','hover','down','down_off','inactive','selected','selected_hover','selected_down','selected_down_off'})do
                checked_state(component,state)
                for layer,variant in ipairs(layers)do
                    local image=layer-1
                    local selected_option=id:match('^wh3ep_lib_filter_option_([a-z]+)$')==filter
                    local variant_role=role[1]=='dropdown'and selected_option and 'dropdown_selected'or role[1]
                    component:SetImagePath('ui/skins/wh3ep/role_'..variant_role..'_'..mode..'_'..variant..'.png',component:GetCurrentStateImageIndex(image),false)
                    component:SetCanResizeCurrentStateImageWidth(image,true);component:SetCanResizeCurrentStateImageHeight(image,true)
                    component:ResizeCurrentStateImage(image,size[1],size[2]);component:SetCurrentStateImageDockingPoint(image,1);component:SetCurrentStateImageDockOffset(image,0,0)
                end
                component:SetText(mode=='fixed'and ''or fitted(component,value),'')
            end
            checked_state(component,current_state);component:Resize(size[1],size[2],false)
            paint_cache[id]=key
        end
        component:SetTooltipText((id=='wh3ep_lib_help'and library_help)or(id=='button_preview_help'and(draft and draft.action=='result'and result_help or preview_help))or value,true);return true
    end
    local function preview_row_y(row)return 174+(row-1)*83+(row==4 and 1 or 0)end
    local function list_row_y(index)return index==1 and 218 or 307+(index-2)*85+(index>=4 and 1 or 0)end
    local normalized_stock={
        ['ui/skins/default/equipment_items_weapon.png']='ui/skins/wh3ep/stock_weapon.png',
        ['ui/skins/default/equipment_items_armour.png']='ui/skins/wh3ep/stock_armour.png',
        ['ui/skins/default/equipment_items_talisman.png']='ui/skins/wh3ep/stock_talisman.png',
        ['ui/skins/default/equipment_items_enchanted.png']='ui/skins/wh3ep/stock_enchanted.png',
        ['ui/skins/default/equipment_items_arcane.png']='ui/skins/wh3ep/stock_arcane.png'
    }
    set_icon=function(component,path,dx,dy,size)
        size=math.floor(size or 56)
        component:SetVisible(false)
        if type(path)~='string'or path==''then return false end
        local compiled=normalized_stock[path];path=compiled or path
        local ok=pcall(function()
            -- Fixed slot: do not replace its metrics with the source file dimensions.
            -- Clear inherited padded-glyph metrics BEFORE resizing/replacing a reused portrait.
            component:SetCurrentStateImageDockingPoint(0,1)
            component:SetCurrentStateImageDockOffset(0,0,0)
            component:SetCanResizeCurrentStateImageWidth(0,true)
            component:SetCanResizeCurrentStateImageHeight(0,true)
            component:ResizeCurrentStateImage(0,size,size)
            component:SetImagePath(path,0,false)
            component:Resize(size,size,false)
            -- Stock art is normalized at build time; every runtime image uses its exact slot canvas.
            local metric,expected_dock,offset=size,1,0
            component:SetCanResizeCurrentStateImageWidth(0,true)
            component:SetCanResizeCurrentStateImageHeight(0,true)
            component:ResizeCurrentStateImage(0,metric,metric)
            component:SetCurrentStateImageDockingPoint(0,expected_dock)
            component:SetCurrentStateImageDockOffset(0,offset,offset)
            if dx then component:MoveTo(x+dx,y+dy)end
            local width,tall=component:Dimensions()
            local image_width,image_height=component:GetCurrentStateImageDimensions(0)
            local offset_x,offset_y=component:GetCurrentStateImageDockOffset(0)
            local dock=component:GetCurrentStateImageDockingPoint(0)
            local valid=width==size and tall==size and image_width==metric and image_height==metric and offset_x==offset and offset_y==offset and dock==expected_dock
            local diagnostic_key=component:Id()..(compiled and '_stock'or '_portrait')..size
            if not reference_logged[diagnostic_key]then
                local pos_x,pos_y=component:Position()
                ModLog('[WH3EP] ui_icon_position='..component:Id()..';xy='..pos_x..','..pos_y)
                ModLog('[WH3EP] ui_icon='..component:Id()..';family='..(compiled and 'stock_compiled'or 'portrait')..';offset='..offset_x..','..offset_y)
                ModLog('[WH3EP] ui_reference_icon_valid='..tostring(valid))
                ModLog('[WH3EP] ui_reference_icon_component='..tostring(width)..'x'..tostring(tall))
                ModLog('[WH3EP] ui_reference_icon_metric='..tostring(image_width)..'x'..tostring(image_height))
                ModLog('[WH3EP] ui_reference_icon_dock='..tostring(dock))
                reference_logged[diagnostic_key]=true
            end
            if not valid then error('icon_geometry',0)end
        end)
        if not ok then ModLog('[WH3EP] ui_reference_icon_error=true;id='..component:Id())end
        component:SetVisible(ok);return ok
    end
    local function graphic(id,style,dx,dy,width,tall,parent)
        local component=core:get_or_create_component(id,'ui/templates/'..style..'.twui.xml',parent or frame)
        if style=='wh3ep_icon'then component:SetCurrentStateImageDockingPoint(0,1);component:SetCurrentStateImageDockOffset(0,0,0)end
        component:PropagatePriority(parent and 221 or 151);component:Resize(width,tall)
        component:MoveTo(x+dx,y+dy);component:SetVisible(true)
        return component
    end
    local function item_tooltip(state,key)
        local name=state and state.names and state.names[key]or L('name_unavailable')
        local effects=state and state.tooltips and state.tooltips[key]
        return name..(type(effects)=='string'and effects~=''and ('\n'..effects)or '')
    end
    local function preset_icon_path(preset,state)
        if preset and preset.icon_key and preset_icons[preset.icon_key]then return 'ui/skins/wh3ep/preset_icon_'..preset.icon_key..'.png' end
        local first=preset and preset.equipment[1]and preset.equipment[1].item_key or preset and preset.followers[1]
        return first and state and state.icons and state.icons[first]or 'ui/skins/wh3ep/empty_preset.png'
    end
    local function preset_icon_tooltip(preset,state)
        if preset and preset.icon_key and preset_icons[preset.icon_key]then return L('preset_icon_'..preset.icon_key)end
        local first=preset and preset.equipment[1]and preset.equipment[1].item_key or preset and preset.followers[1]
        return first and item_tooltip(state,first)or L('empty_loadout')
    end
    local function item_frame(component,state,key)
        local rarity=state and state.rarities and state.rarities[key]
        local allowed={common=true,uncommon=true,rare=true,legendary=true,crafted=true}
        if not allowed[rarity]then rarity='default'end
        local w,h=component:Dimensions()
        component:SetImagePath('ui/skins/wh3ep/rarity_'..rarity..'.png',0,false)
        component:SetCanResizeCurrentStateImageWidth(0,true);component:SetCanResizeCurrentStateImageHeight(0,true)
        component:ResizeCurrentStateImage(0,w,h);component:SetCurrentStateImageDockingPoint(0,1);component:SetCurrentStateImageDockOffset(0,0,0)
    end
    local function make_layout(parent)
        close_filter_menu()
        ModLog('[WH3EP] library_panel_create_begin');reference_logged={};paint_cache={}
        local width,screen_height=parent:Dimensions();local px,py=parent:Position()
        height=math.min(744,screen_height-40)
        x,y=px+math.max(10,math.floor((width-954)/2)),py+math.max(10,math.floor((screen_height-height)/2))
        page_size=math.max(3,math.min(4,math.floor((height-388)/85)))
        frame=core:get_or_create_component('wh3ep_lib_frame','ui/templates/wh3ep_panel.twui.xml',parent)
        container_priority(frame,150);frame:SetCanResizeWidth(true);frame:SetCanResizeHeight(true);frame:Resize(954,height,false);frame:MoveTo(x,y)
        if native_text then frame:SetImagePath('ui/skins/wh3ep/en_panel.png',0,false)end
        -- Absorb hover/clicks through inactive controls; child actions stay disabled.
        frame:SetInteractive(true)
        label('wh3ep_lib_title',L('library_title'),252,20,450,44,nil,'wh3ep_heading'):SetVisible(native_text)
        label('wh3ep_lib_scope','',242,78,470,32,nil,'wh3ep_subtitle')
        controls.search_input=graphic('wh3ep_lib_search_input','wh3ep_library_search',34,154,414,44)
        controls.search_input:SetCanResizeWidth(true);controls.search_input:SetCanResizeHeight(true)
        controls.search_input:SetTooltipText(L('hint_search'),true);text(controls.search_input,query)
        controls.search=button('wh3ep_lib_search',L('button_find'),248,154,74)
        controls.filter=button('wh3ep_lib_filter','',460,154,44,true,'wh3ep_filter')
        filter_menu_open=false
        controls.filter_menu=graphic('wh3ep_lib_filter_menu','wh3ep_card',214,198,300,200)
        controls.filter_menu:PropagatePriority(200)
        controls.filter_menu:SetInteractive(true)
        controls.filter_menu:SetVisible(false)
        for index,key in ipairs(filters)do
            local option=button('wh3ep_lib_filter_option_'..key,filter_names[key],224,206+(index-1)*46,280,true,nil,controls.filter_menu)
            option:PropagatePriority(201)
            option:SetTooltipText(filter_names[key],true)
            text(option,fitted(option,filter_names[key],48))
            option:SetVisible(false)
            controls['filter_option_'..key]=option
        end
        controls.clear=button('wh3ep_lib_clear_search',L('button_reset'),824,95,112,true)
        controls.count=label('wh3ep_lib_count',L('library_presets'),24,184,474,22)
        for index=1,10 do
            local dy=list_row_y(index)
            local component=graphic('wh3ep_lib_row_'..index,'wh3ep_row',24,dy,480,84)
            report_events(component);component:SetVisible(false);button_ids[component:Id()]=true;rows[index]=component
            label('row_name_'..index,'',138,dy+19,300,34,nil,'wh3ep_name')
            label('row_meta_'..index,'',138,dy+51,300,28,nil,'wh3ep_row_meta')
            graphic('row_frame_'..index,'wh3ep_icon_frame',40,dy+13,64,64):SetVisible(false)
            local star=button('row_star_'..index,'',450,dy+22,34,true,'wh3ep_star');star:SetTooltipText(L('hint_favorite'),true);star:SetVisible(false)
        end
        local shift=height<720 and 40 or 0
        graphic('wh3ep_lib_card','wh3ep_card',512,172,418,height-298)
        graphic('card_heading_frame','wh3ep_icon_frame',544,199-shift/2,64,64)
        graphic('card_heading_icon','wh3ep_icon',548,203-shift/2,56,56)
        controls.details=label('wh3ep_lib_details',L('select_loadout'),612,197-shift/2,292,shift>0 and 30 or 38,nil,'wh3ep_name')
        controls.card_scope=label('wh3ep_lib_card_scope','',612,235-shift*0.7,292,shift>0 and 22 or 32,nil,'wh3ep_italic')
        graphic('card_divider','wh3ep_divider',534,270-shift,378,18)
        -- 378 px inner width: 6*56 + 5*8 = 376. Two category rows,
        -- 48 px icons inset by four; the compact-height footer remains clear.
        for index=1,12 do
            local x=534+((index-1)%6)*64;local y=294-shift+math.floor((index-1)/6)*64
            graphic('card_icon_frame_'..index,'wh3ep_icon_frame',x,y,56,56):SetVisible(false)
            local icon=graphic('card_icon_'..index,'wh3ep_icon',x+4,y+4,48,48)
            icon:SetInteractive(true);icon:SetVisible(false)
        end
        controls.card_count=label('wh3ep_lib_card_count','',538,418-shift,374,20,nil,'wh3ep_counter')
        controls.rename=button('wh3ep_lib_rename',L('button_rename'),534,height-276,184,false,'wh3ep_compact_primary')
        controls.overwrite=button('wh3ep_lib_overwrite',L('button_update'),730,height-276,184,false,'wh3ep_compact_primary')
        controls.scope=button('wh3ep_lib_change_scope',L('button_general'),534,height-214,184,true,'wh3ep_compact_secondary')
        controls.delete=button('wh3ep_lib_delete',L('button_delete_ellipsis'),730,height-214,184,true,'wh3ep_compact_secondary')
        controls.favorite=button('wh3ep_lib_favorite','',886,162,34,true,'wh3ep_star')
        controls.previous=button('wh3ep_lib_previous',L('button_previous'),24,height-150,168,true)
        controls.page=label('wh3ep_lib_page','',212,height-132,100,25,nil,'wh3ep_subtitle')
        controls.next=button('wh3ep_lib_next',L('button_next'),334,height-150,170,true)
        controls.previous_arrow=graphic('wh3ep_lib_previous_arrow','wh3ep_icon',34,height-140,18,18)
        set_icon(controls.previous_arrow,'ui/skins/wh3ep/glyph_arrow_back.png',34,height-140,18);controls.previous_arrow:SetInteractive(false)
        controls.next_arrow=graphic('wh3ep_lib_next_arrow','wh3ep_icon',452,height-140,18,18)
        set_icon(controls.next_arrow,'ui/skins/wh3ep/glyph_arrow_forward.png',452,height-140,18);controls.next_arrow:SetInteractive(false)
        controls.save=button('wh3ep_lib_save',L('button_save'),40,height-85,250,false,'wh3ep_compact_primary')
        controls.save_class=button('wh3ep_lib_save_class','',305,height-80,34,true,'wh3ep_radio')
        controls.save_class_label=button('wh3ep_lib_save_class_label',L('radio_class'),339,height-80,98,true,'wh3ep_radio_label')
        controls.save_general=button('wh3ep_lib_save_general','',440,height-80,34,true,'wh3ep_radio')
        controls.save_general_label=button('wh3ep_lib_save_general_label',L('radio_general'),474,height-80,80,true,'wh3ep_radio_general_label')
        controls.apply=button('wh3ep_lib_apply',L('button_preview'),580,height-85,196)
        controls.close=button('wh3ep_lib_close',L('button_close'),788,height-85,142,true)
        graphic('footer_separator','wh3ep_line',555,height-90,1,64)
        controls.help=button('wh3ep_lib_help','?',891,74,38,true,'wh3ep_help');controls.help:Resize(38,38);label_sizes.wh3ep_lib_help={38,38}
        controls.search:SetVisible(false);controls.clear:SetVisible(false);controls.count:SetVisible(false);controls.favorite:SetVisible(false)
        graphic('search_lens','wh3ep_lens',48,162,28,28)
        controls.search_hint=label('search_hint',L('hint_search_placeholder'),88,161,302,32,nil,'wh3ep_search_hint')
        label('library_empty_title','',46,264,430,40,nil,'wh3ep_name'):SetVisible(false)
        label('library_empty_hint','',46,310,430,36,nil,'wh3ep_detail'):SetVisible(false)
        graphic('status_strip','wh3ep_status_strip',16,height-31,922,26)
        controls.status=label('wh3ep_lib_status','',24,height-27,906,20,nil,'wh3ep_feedback')
    end
    render_progress=function(report)
        local running=report.status=='running'or report.status=='awaiting_confirmation'
        if not running or not visible or not frame or not frame:Visible(true)then if progress then progress:SetVisible(false)end;return end
        progress=core:get_or_create_component('wh3ep_apply_progress','ui/templates/wh3ep_panel.twui.xml',frame)
        local left,top=147,math.floor((height-300)/2)
        container_priority(progress,160);progress:SetCanResizeWidth(true);progress:SetCanResizeHeight(true);progress:Resize(660,300,false);progress:MoveTo(x+left,y+top)
        progress:SetImagePath('ui/skins/wh3ep/card.png',0,false);progress:SetInteractive(true);progress:SetVisible(true)
        progress:SetCanResizeCurrentStateImageWidth(0,true);progress:SetCanResizeCurrentStateImageHeight(0,true);progress:ResizeCurrentStateImage(0,660,300);progress:SetCurrentStateImageDockingPoint(0,1);progress:SetCurrentStateImageDockOffset(0,0,0)
        local function field(id,value,dx,dy,w,h,style)
            local c=label(id,value,left+dx,top+dy,w,h,progress,style);c:PropagatePriority(161);return c
        end
        field('progress_title',L('progress_applying'),35,22,590,42,'wh3ep_heading')
        local completed=math.max(0,report.completed or 0);local total=math.max(completed,progress_total or 0)
        field('progress_count',completed..' / '..total,35,80,590,30,'wh3ep_subtitle')
        local track=core:get_or_create_component('progress_track','ui/templates/wh3ep_status_strip.twui.xml',progress)
        track:PropagatePriority(161);track:MoveTo(x+left+35,y+top+119);track:Resize(590,16);track:SetImagePath('ui/skins/wh3ep/progress_track.png',0,false)
        track:SetCanResizeCurrentStateImageWidth(0,true);track:SetCanResizeCurrentStateImageHeight(0,true);track:ResizeCurrentStateImage(0,590,16);track:SetCurrentStateImageDockingPoint(0,1);track:SetCurrentStateImageDockOffset(0,0,0);track:SetVisible(true)
        local fill=core:get_or_create_component('progress_fill','ui/templates/wh3ep_line.twui.xml',progress)
        local fill_width=math.max(1,math.floor(584*(total>0 and math.min(1,completed/total)or 0)))
        fill:PropagatePriority(162);fill:MoveTo(x+left+38,y+top+122);fill:Resize(fill_width,10);fill:SetImagePath('ui/skins/wh3ep/'..(completed>=total and total>0 and 'progress_fill_ready.png'or 'progress_fill.png'),0,false)
        fill:SetCanResizeCurrentStateImageWidth(0,true);fill:SetCanResizeCurrentStateImageHeight(0,true);fill:ResizeCurrentStateImage(0,fill_width,10);fill:SetCurrentStateImageDockingPoint(0,1);fill:SetCurrentStateImageDockOffset(0,0,0);fill:SetVisible(completed>0)
        local message=report.status=='awaiting_confirmation'and L('progress_confirmation')or L('progress_wait')
        field('progress_message',message,35,154,590,44,'wh3ep_detail')
        for _,spec in ipairs({{'wh3ep_progress_verify',L('button_verify'),80},{'wh3ep_progress_stop',L('button_stop'),350}})do
            local c=core:get_or_create_component(spec[1],'ui/templates/wh3ep_primary.twui.xml',progress)
            c:PropagatePriority(161);c:MoveTo(x+left+spec[3],y+top+222);c:Resize(230,48);c:SetVisible(true);report_events(c);button_ids[spec[1]]=true;label_sizes[spec[1]]={230,48}
            checked_state(c,spec[1]=='wh3ep_progress_verify'and not adapter.apply.waiting()and 'inactive'or 'active');text(c,spec[2]);c:SetTooltipText(spec[1]=='wh3ep_progress_verify'and L('hint_verify_continue')or L('hint_stop_preserve'),true)
        end
        -- No LockPriority/RegisterTopMost: native donor confirmation must remain usable.
    end
    render=function()
        if not frame or not current then return end
        close_filter_menu()
        if not apply_busy()then refresh_display()end
        diagnostic_stage='list'
        local list=library and model.list(library,current.faction_key,current.class_key,filter,query,current.character_kind) or {}
        list=list or {}
        diagnostic_stage='pagination'
        local pages=math.max(1,math.ceil(#list/page_size));library_pages=pages;page=math.max(1,math.min(page,pages))
        local selected_index
        for index,preset in ipairs(list)do if preset.id==selected_id then selected_index=index;break end end
        if selected_index then page=math.floor((selected_index-1)/page_size)+1
        else local first=list[(page-1)*page_size+1];selected_id=first and first.id or nil end
        diagnostic_stage='rows'
        for index,component in ipairs(rows)do
            local preset=index<=page_size and list[(page-1)*page_size+index] or nil
            component:SetVisible(preset~=nil)
            if preset then component:Resize(480,84,false)end
            find_uicomponent(frame,'row_frame_'..index):SetVisible(false)
            find_uicomponent(frame,'row_name_'..index):SetVisible(preset~=nil)
            find_uicomponent(frame,'row_meta_'..index):SetVisible(preset~=nil)
            find_uicomponent(frame,'row_star_'..index):SetVisible(preset~=nil);row_favorites[index]=preset and preset.favorite or false
            local row_icon=find_uicomponent(frame,'row_icon_'..index);if row_icon then row_icon:SetVisible(false)end
            local old_slot=find_uicomponent(frame,'row_item_frame_'..index);if old_slot then old_slot:SetVisible(false)end
            if preset then
                local first=preset.equipment[1]and preset.equipment[1].item_key or preset.followers[1]
                local row_y=list_row_y(index)+(preset.id==selected_id and 12 or 10)
                local row_frame=graphic('row_item_frame_'..index,'wh3ep_icon_frame',30,row_y-4,72,72)
                -- Create the glyph after its opaque frame so the native sibling draw order cannot bury it.
                if not row_icon then row_icon=graphic('row_icon_'..index,'wh3ep_icon',34,row_y,64,64);report_events(row_icon)end
                if preset.icon_key and preset_icons[preset.icon_key]then item_frame(row_frame,nil,nil)else item_frame(row_frame,display_state,first)end
                local frame_priority=row_frame:Priority()
                row_frame:PropagatePriority(frame_priority);row_icon:PropagatePriority(frame_priority+1)
                set_icon(row_icon,preset_icon_path(preset,display_state),34,row_y,64)
                row_frame:SetVisible(not (preset.icon_key and preset_icons[preset.icon_key]))
                row_icon:SetInteractive(true);row_icon:SetTooltipText(preset_icon_tooltip(preset,display_state),true)
                set_base(component,preset.id==selected_id and 'selected'or 'active')
                for image=0,6 do
                    component:SetCanResizeCurrentStateImageWidth(image,true);component:SetCanResizeCurrentStateImageHeight(image,true)
                    component:ResizeCurrentStateImage(image,480,preset.id==selected_id and 88 or 84)
                    component:SetCurrentStateImageDockingPoint(image,1);component:SetCurrentStateImageDockOffset(image,0,0)
                end
                local name_label=find_uicomponent(frame,'row_name_'..index);text(name_label,fitted(name_label,preset.name))
                text(find_uicomponent(frame,'row_meta_'..index),(preset.class_key==''and L('label_general')or L('label_class')))
                component:SetTooltipText(preset.name,true)
            end
        end
        local faction=library and library.factions[current.faction_key]
        local any=faction and #faction.presets>0
        local empty_title=query~=''and L('empty_search')or not any and L('empty_library')or filter=='favorites'and L('empty_favorites')or L('empty_matching')
        local empty_hint=query~=''and L('empty_search_hint')or not any and L('empty_library_hint')or filter=='favorites'and L('empty_favorites_hint')or L('empty_matching_hint')
        for _,pair in ipairs({{'library_empty_title',empty_title},{'library_empty_hint',empty_hint}})do
            local component=find_uicomponent(frame,pair[1]);component:SetVisible(#list==0);text(component,fitted(component,pair[2]));component:SetTooltipText(pair[2],true)
        end
        diagnostic_stage='labels'
        text(controls.count,L('presets_prefix')..tostring(#list))
        text(controls.page,tostring(page)..' / '..tostring(pages))
        for _,state in ipairs({'active','hover','down','down_off','inactive','selected','selected_hover','selected_down','selected_down_off'})do
            checked_state(controls.filter,state)
            for layer,variant in ipairs({'active','hover','down','inactive'})do
                local image=layer-1
                controls.filter:SetImagePath('ui/skins/wh3ep/filter_'..filter..'_'..variant..'.png',controls.filter:GetCurrentStateImageIndex(image),false)
                controls.filter:SetCanResizeCurrentStateImageWidth(image,true);controls.filter:SetCanResizeCurrentStateImageHeight(image,true);controls.filter:ResizeCurrentStateImage(image,44,44)
                controls.filter:SetCurrentStateImageDockingPoint(image,1);controls.filter:SetCurrentStateImageDockOffset(image,0,0)
            end
        end
        checked_state(controls.filter,'active');text(controls.filter,'');controls.filter:SetTooltipText(filter_names[filter],true)
        if controls.search_input:GetStateText()~=query then text(controls.search_input,query)end
        controls.search_hint:SetVisible(query=='')
        controls.previous:SetVisible(pages>1);controls.next:SetVisible(pages>1);controls.page:SetVisible(pages>1)
        controls.previous_arrow:SetVisible(pages>1);controls.next_arrow:SetVisible(pages>1)
        local scope_label=find_uicomponent(frame,'wh3ep_lib_scope');local scope_text=current.name or (current.character_kind=='hero'and L('character_hero')or L('character_lord'))
        text(scope_label,fitted(scope_label,scope_text));scope_label:SetTooltipText(scope_text,true)
        button_text('save_class_label',L('radio_class'))
        button_text('save_general_label',L('radio_general'))
        local shift=height<720 and 40 or 0
        for index=1,card_slots do find_uicomponent(frame,'card_icon_'..index):SetVisible(false);find_uicomponent(frame,'card_icon_frame_'..index):SetVisible(false)end
        local preset=chosen()
        if preset then
            text(controls.details,fitted(controls.details,preset.name));controls.details:SetTooltipText(preset.name,true)
            text(controls.card_scope,preset.class_key==''and L('scope_general')or(preset.class_key==current.class_key and preset.character_kind==current.character_kind and L('scope_current_class')or L('label_class')))
            text(controls.card_count,localization.quantity(#preset.equipment,'item')..' · '..localization.quantity(#preset.followers,'follower'))
            local keys={};for _,item in ipairs(preset.equipment)do keys[#keys+1]=item.item_key end
            for _,key in ipairs(preset.followers)do keys[#keys+1]=key end
            -- Special roles can expose more entries than the normal6+6 card.
            -- Fit both entire categories; keep the normal48px icon size unchanged.
            local columns=math.max(6,#preset.equipment,#preset.followers)
            local gap=columns<=6 and 8 or columns<=12 and 4 or 1
            local size=math.min(56,math.floor((378-(columns-1)*gap)/columns))
            if size<4 then gap=0;size=math.floor(378/columns)end
            local inset=math.min(4,math.floor((size-1)/2));local icon_size=size-inset*2
            for index=1,columns*2 do
                local row=math.floor((index-1)/columns);local col=(index-1)%columns
                local key=row==0 and preset.equipment[col+1]and preset.equipment[col+1].item_key or row==1 and preset.followers[col+1]or nil
                local dx=534+col*(size+gap);local dy=294-shift+row*(size+8)
                if index>card_slots then
                    graphic('card_icon_frame_'..index,'wh3ep_icon_frame',dx,dy,size,size):SetVisible(false)
                    local extra=graphic('card_icon_'..index,'wh3ep_icon',dx+inset,dy+inset,icon_size,icon_size);extra:SetInteractive(true);extra:SetVisible(false)
                    card_slots=index
                end
                local slot=find_uicomponent(frame,'card_icon_frame_'..index);slot:MoveTo(x+dx,y+dy);slot:Resize(size,size)
                local icon=find_uicomponent(frame,'card_icon_'..index)
                icon:MoveTo(x+dx+inset,y+dy+inset);icon:Resize(icon_size,icon_size)
                if key then
                    slot:SetVisible(true);item_frame(slot,display_state,key)
                    set_icon(icon,display_state and display_state.icons and display_state.icons[key]or 'ui/skins/wh3ep/empty_preset.png',dx+inset,dy+inset,icon_size)
                    icon:SetTooltipText(item_tooltip(display_state,key),true)
                end
            end
            if #keys==0 then
                local placeholder_frame=find_uicomponent(frame,'card_icon_frame_1');local placeholder=find_uicomponent(frame,'card_icon_1')
                placeholder_frame:SetVisible(true);item_frame(placeholder_frame,nil,nil)
                set_icon(placeholder,'ui/skins/wh3ep/empty_preset.png',538,298-shift,48)
                placeholder:SetInteractive(true);placeholder:SetTooltipText(L('empty_loadout'),true)
            end
            controls.favorite_selected=preset.favorite
            local first=keys[1]
            local heading_slot=find_uicomponent(frame,'card_heading_frame');heading_slot:SetVisible(true)
            heading_slot:MoveTo(x+(shift>0 and 544 or 536),y+(shift>0 and 174 or 188));heading_slot:Resize(shift>0 and 56 or 76,shift>0 and 56 or 76)
            if preset.icon_key and preset_icons[preset.icon_key]then item_frame(heading_slot,nil,nil)else item_frame(heading_slot,display_state,first)end
            heading_slot:SetVisible(not (preset.icon_key and preset_icons[preset.icon_key]))
            set_icon(find_uicomponent(frame,'card_heading_icon'),preset_icon_path(preset,display_state),shift>0 and 546 or 540,shift>0 and 176 or 192,preset.icon_key and preset_icons[preset.icon_key]and (shift>0 and 52 or 68)or (shift>0 and 48 or 68))
            local heading=find_uicomponent(frame,'card_heading_icon');heading:SetInteractive(true);heading:SetTooltipText(preset_icon_tooltip(preset,display_state),true)
            button_text('scope',preset.class_key=='' and L('label_class') or L('button_general'))
        else text(controls.details,L('select_loadout'));text(controls.card_scope,'');text(controls.card_count,'');controls.favorite_selected=false;for _,id in ipairs({'card_heading_frame','card_heading_icon'})do find_uicomponent(frame,id):SetVisible(false)end end
        apply_buttons()
        button_text('delete',library_status=='backup_available' and L('button_restore') or L('button_delete'))
    end
    local function preview_owner(plan,item)
        local state=plan.state;local names,seen={},{}
        local function add(owner)
            local donor=(state.donors or{})[owner]
            if donor and not seen[owner]then seen[owner]=true;names[#names+1]=donor.name or (donor.character_kind=='lord'and L('character_lord')or L('character_hero'))end
        end
        if item.status=='donor'then add(item.candidate.owner)
        elseif item.status=='occupied'then
            for _,instance in ipairs(state.instances or{})do
                if instance.key==item.key and instance.owner~=0 and instance.owner~=state.target.cqi and not instance.hidden
                    and (item.category=='general'and instance.category=='general'or item.category~='general'and instance.category~='general'and item.slot_key==instance.slot_key)then add(instance.owner)end
            end
        end
        if #names==0 then return L('owner_unavailable')end
        table.sort(names);local shown={};for i=1,math.min(#names,8)do shown[i]=names[i]end
        return table.concat(shown,', ')..(#names>8 and L('format_more_owners',#names-8)or '')
    end
    render_apply_preview=function()
        if not draft or draft.action~='apply'then return end
        local plan=draft.plan;local pages=math.max(1,math.ceil(#plan.entries/4))
        draft.page=math.max(1,math.min(draft.page or 1,pages))
        local labels={already=L('item_already'),free=L('item_free'),missing=L('item_missing'),occupied=L('item_occupied'),
            incompatible=L('item_incompatible'),unsupported=L('item_unsupported'),no_slot=L('item_no_slot')}
        local summary=plan.summary or{}
        local skipped=#plan.entries-#plan.actions-(summary.already or 0)
        text(find_uicomponent(popup,'apply_preview'),L('preview_equip_prefix')..#plan.actions..L('preview_already_separator')..(summary.already or 0)..L('preview_skipped_separator')..skipped..'.')
        local summary_labels={
            {'summary_equip',L('summary_equip_prefix')..#plan.actions},
            {'summary_already',L('summary_already_prefix')..(summary.already or 0)},
            {'summary_skipped',L('summary_unavailable_prefix')..skipped}
        }
        for _,entry in ipairs(summary_labels)do
            local component=find_uicomponent(popup,entry[1]);text(component,fitted(component,entry[2],8));component:SetTooltipText(entry[2],true)
        end
        local categories={weapon=L('category_weapon'),armour=L('category_armour'),armor=L('category_armour'),talisman=L('category_talisman'),enchanted_item=L('category_enchanted'),arcane_item=L('category_arcane')}
        for row=1,4 do
            local i=(draft.page-1)*4+row
            local item=plan.entries[i]
            local label=find_uicomponent(popup,'apply_row_'..row)
            local icon=find_uicomponent(popup,'apply_icon_'..row)
            local placeholder=find_uicomponent(popup,'apply_placeholder_'..row)
            label:SetVisible(item~=nil);icon:SetVisible(false);placeholder:SetVisible(false)
            find_uicomponent(popup,'apply_icon_frame_'..row):SetVisible(item~=nil)
            find_uicomponent(popup,'apply_bg_'..row):SetVisible(item~=nil)
            find_uicomponent(popup,'apply_state_icon_'..row):SetVisible(false)
            find_uicomponent(popup,'apply_status_art_'..row):SetVisible(false)
            find_uicomponent(popup,'apply_separator_'..row):SetVisible(item~=nil)
            find_uicomponent(popup,'apply_status_'..row):SetVisible(item~=nil)
            find_uicomponent(popup,'apply_detail_'..row):SetVisible(item~=nil)
            if item then
                local category=item.category=='general'and L('category_follower')or categories[item.slot_key]or L('category_item')
                local lines={};local item_name=plan.state.names[item.key]or L('name_unavailable')
                text(label,fitted(label,item_name));label:SetTooltipText(item_name,true)
                local source
                if item.status=='donor'or item.status=='occupied'then source=preview_owner(plan,item)end
                if item.status=='donor'then lines[#lines+1]=L('item_transfer')
                else lines[#lines+1]=labels[item.status]or L('item_unavailable')end
                if item.replacement then lines[#lines+1]=L('item_reserve_prefix')..(plan.state.names[item.replacement.key]or L('item_current'))
                elseif item.status=='free'or item.status=='donor'then lines[#lines+1]=L('item_free_slot')
                elseif item.status=='already'then lines[#lines+1]=L('item_unchanged')
                else lines[#lines+1]=L('item_preserved')end
                local status_label=find_uicomponent(popup,'apply_status_'..row)
                checked_state(status_label,item.status=='already'and 'good'or (item.status=='free'and 'available'or 'warning'))
                text(status_label,fitted(status_label,lines[1],0));status_label:SetTooltipText(item.status=='no_slot'and L('item_no_free_slot')or lines[1],true)
                local state_icon=find_uicomponent(popup,'apply_state_icon_'..row)
                local glyphs={already='already',free='free',donor='donor',occupied='occupied',missing='missing',incompatible='incompatible',unsupported='unsupported',no_slot='no_slot'}
                state_icon:SetVisible(true);state_icon:SetImagePath('ui/skins/wh3ep/glyph_'..(glyphs[item.status]or 'skipped')..'.png',0,false)
                state_icon:Resize(32*draft.scale,32*draft.scale,false)
                local detail=find_uicomponent(popup,'apply_detail_'..row)
                local detail_text=lines[2] -- Preserve the action/preservation message; category remains in full tooltip.
                if item.status=='occupied'then
                    local suffix=L('transfer_off_suffix')
                    detail_text=fitted(detail,clipped(source,26),8+detail:WidthOfTextLine(suffix))..suffix
                end
                if item.status=='already'then detail_text=''end
                if item.status=='free'or item.status=='donor'then detail_text=(source and (clipped(source,20)..' · ')or '')..(item.replacement and (L('item_replaces_prefix')..clipped(plan.state.names[item.replacement.key]or L('item_current'),35))or L('item_slot_free'))end
                text(detail,fitted(detail,detail_text))
                -- A single-line entry is vertically centered; source/replacement rows keep two baselines.
                local row_y=preview_row_y(row)
                local top_offset=detail_text==''and 21 or 12
                label:MoveTo(x+draft.left+142*draft.scale,y+draft.top+(row_y+top_offset)*draft.scale)
                status_label:MoveTo(x+draft.left+452*draft.scale,y+draft.top+(row_y+top_offset+3)*draft.scale)
                state_icon:MoveTo(x+draft.left+412*draft.scale,y+draft.top+(row_y+19)*draft.scale)
                status_label:MoveTo(x+draft.left+452*draft.scale,y+draft.top+(row_y+19)*draft.scale)
                find_uicomponent(popup,'apply_status_art_'..row):SetVisible(false)
                detail:SetTooltipText(category..(source and (L('item_owner_line')..source)or '')..'\n'..lines[2],true)
                local path=plan.state.icons and plan.state.icons[item.key]or 'ui/skins/wh3ep/empty_preset.png'
                item_frame(find_uicomponent(popup,'apply_icon_frame_'..row),plan.state,item.key)
                local shown=set_icon(icon,path,draft.left+54*draft.scale,draft.top+(preview_row_y(row)+7)*draft.scale,64*draft.scale)
                icon:SetInteractive(true);icon:SetTooltipText(item_tooltip(plan.state,item.key),true)
                placeholder:SetVisible(not shown)
            end
        end
        if #plan.entries==0 then text(find_uicomponent(popup,'apply_preview'),L('preview_empty'))end
        text(find_uicomponent(popup,'preview_take_label'),L('label_take'))
        text(find_uicomponent(popup,'preview_page'),draft.page..' / '..pages)
        set_base(find_uicomponent(popup,'button_preview_previous'),draft.page==1 and 'inactive'or 'active')
        set_base(find_uicomponent(popup,'button_preview_next'),draft.page==pages and 'inactive'or 'active')
        set_icon(find_uicomponent(popup,'button_preview_previous_arrow'),'ui/skins/wh3ep/glyph_arrow_back'..(draft.page==1 and '_inactive'or '')..'.png',draft.left+90*draft.scale,draft.top+602*draft.scale,18*draft.scale)
        set_icon(find_uicomponent(popup,'button_preview_next_arrow'),'ui/skins/wh3ep/glyph_arrow_forward'..(draft.page==pages and '_inactive'or '')..'.png',draft.left+556*draft.scale,draft.top+602*draft.scale,18*draft.scale)
        set_base(find_uicomponent(popup,'button_preview_take'),take and 'selected'or 'active')
        set_base(find_uicomponent(popup,'preview_take_label'),take and 'selected'or 'active')
    end
    open_popup=function(action,title,initial,payload)
        if cm and cm.remove_real_callback then cm:remove_real_callback('wh3ep_library_form')end
        payload=payload or {}
        payload.action=action;payload.cqi=selected_cqi;payload.faction=current.faction_key
        if action=='create'then payload.icon_key='general'elseif action=='rename'and not preset_icons[payload.icon_key]then payload.icon_key='general'end
        draft=payload
        ModLog('[WH3EP] library_input_begin')
        ModLog('[WH3EP] library_input_action='..action)
        -- PopupTextInput owns descendant layout; its input was missing on live confirmation.
        -- Compose stock components without that callback; Lua owns this lifetime.
        release_popup_native()
        local modal_parent=find_uicomponent(core:get_ui_root(),'character_details_panel')
        if not modal_parent then return end
        popup=core:get_or_create_component('wh3ep_lib_input_popup','ui/templates/wh3ep_panel.twui.xml',modal_parent)
        local icon_form=action=='create'or action=='rename'
        local tall=action=='apply'and math.min(756,height+12)or action=='result'and 420 or icon_form and 540 or 300
        local scale=action=='apply'and tall/756 or 1
        local width=660*scale;local left=(954-width)/2;local top=(height-tall)/2
        draft.top,draft.left,draft.scale=top,left,scale
        container_priority(popup,220);popup:SetCanResizeWidth(true);popup:SetCanResizeHeight(true);popup:Resize(width,tall,false);popup:MoveTo(x+left,y+top)
        popup:SetImagePath(action=='apply'and ('ui/skins/wh3ep/'..(native_text and 'en_preview_panel_titled'or 'preview_panel_titled')..'.png')or action=='result'and 'ui/skins/wh3ep/result_panel.png'or 'ui/skins/wh3ep/card.png',0,false)
        local function pgraphic(id,style,dx,dy,w,h)
            return graphic(id,style,left+dx*scale,top+dy*scale,w*scale,h*scale,popup)
        end
        local function plabel(id,value,dx,dy,w,h,style)
            return label(id,value,left+dx*scale,top+dy*scale,w*scale,h*scale,popup,style)
        end
        local function dialog_button(id,caption,dx,dy,w,h,style)
            local component=core:get_or_create_component(id,'ui/templates/'..(style or (id=='button_ok'and 'wh3ep_primary'or 'wh3ep_secondary'))..'.twui.xml',popup)
            component:PropagatePriority(221);component:Resize(w*scale,h*scale)
            component:MoveTo(x+left+dx*scale,y+top+dy*scale);component:SetVisible(true);report_events(component)
            label_sizes[id]={w*scale,h*scale};text_insets[id]=button_inset(id)*scale;base_states[id]='active';checked_state(component,'active');text(component,caption)
            return component
        end
        plabel('panel_title',title,65,19,530,48,'wh3ep_heading'):SetVisible(action~='apply'or native_text)
        local input=pgraphic('text_input','wh3ep_form_input',30,125,600,46)
        input:SetCanResizeWidth(true);input:SetCanResizeHeight(true)
        input:SetVisible(action=='create'or action=='rename'or action=='search');text(input,initial or '')
        local form=action~='apply'and action~='result'
        local context=action=='create'and(payload.class_key==''and L('scope_general')or L('scope_selected_class'))or(action=='delete'or action=='overwrite')and(initial or '')or ''
        local context_label=plabel('form_context','',30,78,600,34,'wh3ep_subtitle')
        context_label:SetVisible(form and context~='');text(context_label,fitted(context_label,context));context_label:SetTooltipText(context,true)
        local hint=action=='delete'and L('hint_delete')or action=='overwrite'and L('hint_overwrite')or ''
        local form_hint=plabel('form_hint','',30,125,600,46,'wh3ep_subtitle');form_hint:SetVisible(form and hint~='');text(form_hint,fitted(form_hint,hint));form_hint:SetTooltipText(hint,true)
        plabel('form_counter','',60,175,540,24,'wh3ep_feedback'):SetVisible(action=='create'or action=='rename')
        plabel('form_feedback','',30,200,600,24,'wh3ep_feedback'):SetVisible(false)
        if icon_form then
            plabel('preset_icon_picker_heading',L('icon_picker_heading'),30,224,600,24,'wh3ep_subtitle')
            for index,key in ipairs(model.preset_icon_keys())do
                local column=(index-1)%5;local row=math.floor((index-1)/5)
                local cell_x=30+column*120;local tile_y=248+row*90
                local caption=L('preset_icon_'..key)
                local tile=dialog_button('preset_icon_option_'..key,'',cell_x+24,tile_y,72,72,'wh3ep_preset_icon_option')
                for _,state in ipairs({'active','hover','down','down_off','inactive','selected','selected_hover','selected_down','selected_down_off'})do checked_state(tile,state);text(tile,'')end
                checked_state(tile,'active');tile:SetTooltipText(caption,true)
                local art=pgraphic('preset_icon_art_'..key,'wh3ep_icon',cell_x+32,tile_y+8,56,56)
                set_icon(art,'ui/skins/wh3ep/preset_icon_'..key..'.png',left+(cell_x+32)*scale,top+(tile_y+8)*scale,56*scale)
                art:SetInteractive(false);art:SetTooltipText(caption,true)
            end
            for _,key in ipairs(model.preset_icon_keys())do set_base(find_uicomponent(popup,'preset_icon_option_'..key),key==draft.icon_key and 'selected'or 'active')end
        else
            for _,key in ipairs(model.preset_icon_keys())do for _,prefix in ipairs({'preset_icon_option_','preset_icon_art_'})do local old=find_uicomponent(popup,prefix..key);if old then old:SetVisible(false)end end end
            local old=find_uicomponent(popup,'preset_icon_picker_heading');if old then old:SetVisible(false)end
        end
        refresh_form()
        if action=='create'or action=='rename'then cm:repeat_real_callback(function()guarded(refresh_form)end,200,'wh3ep_library_form')end
        local result_body=find_uicomponent(popup,'result_summary');if result_body then result_body:SetVisible(false)end
        for _,id in ipairs({'result_count_1','result_count_2','result_count_3','result_icon_1','result_icon_2','result_icon_3','result_subtitle','result_divider','result_status_strip'})do local old=find_uicomponent(popup,id);if old then old:SetVisible(false)end end
        if action=='result'then
            plabel('result_subtitle',terminal_reasons[payload.report.status]and L('result_confirmed')or L('result_subtitle'),112,67,438,30,'wh3ep_preview_subtitle')
            pgraphic('result_divider','wh3ep_line',30,310,600,1)
            local r=payload.report;local sum=r.summary or{};local skipped=0
            for code,n in pairs(sum)do if code~='free'and code~='donor'and code~='already'then skipped=skipped+n end end
            local stopped=terminal_reasons[r.status]
            local captions=stopped and {L('confirmed_prefix')..(r.completed or 0),L('result_halted'),L('result_new_check')}or {L('result_equipped_prefix')..(r.completed or 0),L('already_prefix')..(sum.already or 0),L('skipped_prefix')..skipped}
            local result_glyphs=stopped and {'equipped','warning','missing'}or {'equipped','already','skipped'}
            local group_width=0
            for i,style in ipairs(stopped and {'good','warning','available'}or {'good','available','warning'})do
                local icon_y=132+(i-1)*34;local row_y=icon_y-2
                local lab=plabel('result_count_'..i,captions[i],30,row_y,452,32,'wh3ep_status')
                local measured=lab:WidthOfTextLine(captions[i])
                if localization.language=='cn'or localization.language=='zh'or localization.language=='ja'or localization.language=='kr'then
                    local _,characters=prefix(captions[i],512);measured=math.max(measured,characters*20)
                end
                local label_width=math.min(440,math.ceil(measured)+16)
                group_width=math.max(group_width,label_width)
                local group_left=110
                lab:Resize(label_width,32);lab:MoveTo(x+left+group_left+40,y+top+row_y);label_sizes[lab:Id()]={label_width,32}
                checked_state(lab,style);text(lab,fitted(lab,captions[i],6));lab:SetTooltipText(captions[i],true)
                local glyph=result_glyphs[i];local asset=glyph=='warning'and 'state_warning'or 'glyph_'..glyph
                local ico=pgraphic('result_icon_'..i,'wh3ep_state_icon',group_left,icon_y-2,32,32);ico:SetImagePath('ui/skins/wh3ep/'..asset..'.png',0,false)
            end
            local group_x=math.floor((660-(44+group_width))/2)
            for i=1,3 do
                local lab=find_uicomponent(popup,'result_count_'..i)
                local ico=find_uicomponent(popup,'result_icon_'..i)
                lab:MoveTo(x+left+group_x+44,y+top+130+(i-1)*34);lab:Resize(group_width,32,false)
                label_sizes[lab:Id()]={group_width,32}
                ico:MoveTo(x+left+group_x,y+top+130+(i-1)*34)
            end
            local details=stopped or (L('result_missing_compact')..(sum.missing or 0)..' · '..L('result_incompatible_compact')..(sum.incompatible or 0)..' · '..L('result_occupied_compact')..(sum.occupied or 0)..'\n'..L('result_no_slot_compact')..(sum.no_slot or 0)..' · '..L('result_unsupported_compact')..(sum.unsupported or 0))
            pgraphic('result_status_strip','wh3ep_status_strip',30,235,600,68)
            local result_details=plabel('result_summary',details,46,243,568,52,'wh3ep_detail');result_details:SetTooltipText(details..(stopped and r.code and ('\n'..explain(r.code))or ''),true)
        end
        if action=='apply'then
            local subtitle_text=payload.preset.name
            local subtitle=plabel('preview_subtitle','',112,67,438,30,'wh3ep_preview_ribbon');text(subtitle,fitted(subtitle,subtitle_text,438*0.15));subtitle:SetTooltipText(subtitle_text,true)
            pgraphic('preview_summary','wh3ep_summary',30,122,600,43)
            plabel('summary_equip','',40,127,185,30,'wh3ep_summary_text')
            plabel('summary_already','',235,127,185,30,'wh3ep_summary_text')
            plabel('summary_skipped','',437,127,185,30,'wh3ep_summary_text')
            plabel('apply_preview','',30,122,600,43):SetVisible(false)
            for row=1,4 do
                local dy=preview_row_y(row)
                pgraphic('apply_bg_'..row,'wh3ep_preview_row',30,dy,600,82)
                plabel('apply_row_'..row,'',142,dy+9,270,38,'wh3ep_name'):SetInteractive(true)
                plabel('apply_status_'..row,'',452,dy+19,178,32,'wh3ep_preview_status')
                plabel('apply_detail_'..row,'',142,dy+42,480,28,'wh3ep_preview_detail')
                plabel('apply_placeholder_'..row,'?',54,dy+12,64,64,'wh3ep_subtitle'):PropagatePriority(222)
                pgraphic('apply_icon_frame_'..row,'wh3ep_icon_frame',48,dy,76,80):SetVisible(false)
                pgraphic('apply_icon_'..row,'wh3ep_icon',54,dy+7,64,64):SetVisible(false)
                pgraphic('apply_state_icon_'..row,'wh3ep_state_icon',414,dy+19,28,28):SetVisible(false)
                pgraphic('apply_status_art_'..row,'wh3ep_icon',446,dy+10,203,32):SetVisible(false)
                pgraphic('apply_separator_'..row,'wh3ep_line',40,dy+80,580,1)
            end
            dialog_button('button_preview_take','',46,520,34,40,'wh3ep_checkbox')
            dialog_button('preview_take_label',L('label_take'),90,514,530,40,'wh3ep_toggle_label')
            plabel('preview_hint',L('preview_hint'),90,550,530,30,'wh3ep_preview_hint')
            plabel('preview_page','',285,594,115,34,'wh3ep_subtitle')
            dialog_button('button_preview_previous',L('button_previous'),78,592,168,38,'wh3ep_primary')
            dialog_button('button_preview_next',L('button_next'),416,592,170,38,'wh3ep_primary')
            local previous_arrow=pgraphic('button_preview_previous_arrow','wh3ep_icon',90,602,18,18)
            set_icon(previous_arrow,'ui/skins/wh3ep/glyph_arrow_back.png',left+90*scale,top+602*scale,18*scale);previous_arrow:SetInteractive(false)
            local next_arrow=pgraphic('button_preview_next_arrow','wh3ep_icon',556,602,18,18)
            set_icon(next_arrow,'ui/skins/wh3ep/glyph_arrow_forward.png',left+556*scale,top+602*scale,18*scale);next_arrow:SetInteractive(false)
            dialog_button('button_preview_help','?',27,62,38,38,'wh3ep_help')
            dialog_button('button_preview_close','×',597,62,38,38,'wh3ep_help')
            render_apply_preview()
        else
            for row=1,4 do
                for _,prefix in ipairs({'apply_row_','apply_status_art_','apply_status_','apply_detail_','apply_icon_','apply_icon_frame_','apply_placeholder_','apply_bg_','apply_state_icon_','apply_separator_'})do
                    local child=find_uicomponent(popup,prefix..row);if child then child:SetVisible(false)end
                end
            end
            for _,id in ipairs({'apply_preview','preview_subtitle','preview_hint','preview_page','button_preview_take','button_preview_previous','button_preview_next','button_preview_previous_arrow','button_preview_next_arrow','preview_summary','summary_equip','summary_already','summary_skipped','button_preview_help','button_preview_close','preview_take_label'})do
                local child=find_uicomponent(popup,id);if child then child:SetVisible(false)end
            end
        end
        dialog_button('button_ok',action=='apply'and L('button_apply')or action=='result'and L('button_done')or action=='delete'and L('button_delete')or L('button_confirm'),action=='result'and 170 or action=='apply'and 52 or 46,action=='apply'and 667 or action=='result'and tall-80 or icon_form and tall-80 or tall-70,320,54,action=='apply'and 'wh3ep_apply'or nil)
        dialog_button('button_cancel',L('button_cancel'),action=='apply'and 398 or 395,action=='apply'and 667 or action=='result'and tall-80 or icon_form and tall-80 or tall-70,210,54)
        if action=='result'then
            find_uicomponent(popup,'button_cancel'):SetVisible(false)
            dialog_button('button_preview_help','?',27,62,38,38,'wh3ep_help')
            dialog_button('button_preview_close','×',597,62,38,38,'wh3ep_help')
        end
        popup:SetVisible(true)
        frame:SetVisible(false);if entry then entry:SetVisible(false)end
        popup_topmost=true;popup:RegisterTopMost()
        popup_lock_owner=core:get_ui_root();popup_locked=true;popup_lock_owner:LockPriority(220)
        ModLog('[WH3EP] library_input_ready')
    end
    local function popup_error(code)
        local feedback=find_uicomponent(popup,'form_feedback')
        text(feedback,fitted(feedback,explain(code)));feedback:SetTooltipText(explain(code),true);feedback:SetVisible(true)
        status(explain(code))
    end
    local function accept_popup()
        if not draft then return end
        if panel_cqi()~=selected_cqi then close();entry_caption(L('library_presets'),L('hint_character_changed'));return end
        diagnostic_stage='input_accept'
        ModLog('[WH3EP] library_input_accept')
        if draft.cqi~=selected_cqi or not current or draft.faction~=current.faction_key then close_popup();status(L('error_character_changed'));return end
        local action=draft.action
        if action=='result'then local r=draft.report;close_popup();status(report_text(r):match('^[^\n]+'));return end
        local value=''
        if action=='create' or action=='rename' or action=='search'then
            local input=find_uicomponent(popup,'text_input')
            if not input then popup_error('input_unavailable');return end
            value=input:GetStateText()
            if action=='create'or action=='rename'then value=prefix(value,30)end
        end
        if action=='apply'then
            local plan,preset=draft.plan,draft.preset
            close_popup()
            progress_total=#plan.actions
            ModLog('[WH3EP] apply_begin')
            local target=selected_cqi
            local invalidating=false
            local started,code=adapter.apply.start(target,preset,take,plan,function(report)
                if invalidating then return end
                if selected_cqi==target and panel_cqi()==target then on_apply_update(report)
                else
                    -- cancel() may synchronously notify a pending donor: latch before closing.
                    invalidating=true;close();entry_caption(L('library_presets'),L('hint_character_changed'));invalidating=false
                end
            end)
            if not started then status(explain(code))end
            return
        end
        if action=='search' then
            if type(value)~='string' or #value>512 then popup_error('invalid_name');return end
            query,page,selected_id=value,1,nil;close_popup();render();status(query=='' and L('status_search_cleared') or L('status_search_results'));return
        end
        if action=='restore' then
            local restored,code,info=storage.restore_backup(metadata.token)
            close_popup()
            if restored then library,library_status,metadata=restored,'ok',info;render();status(L('status_restored'))
            else reload();render();status(explain(code))end
            return
        end
        if not writable()then close_popup();return end
        diagnostic_stage='mutation'
        local updated,result
        if action=='create' then updated,result=model.add(library,draft.snapshot,value,draft.class_key,draft.icon_key or 'general')
        elseif action=='rename' then updated,result=model.update(library,current.faction_key,draft.id,{name=value,icon_key=draft.icon_key or 'general'})
        elseif action=='overwrite' then updated,result=model.update(library,current.faction_key,draft.id,{equipment=draft.snapshot.equipment,followers=draft.snapshot.followers,character_kind=draft.snapshot.character_kind})
        elseif action=='delete' then updated,result=model.delete(library,current.faction_key,draft.id)end
        if not updated then popup_error(result);return end
        if action=='create' then filter,query,page='matching','',1 end
        if action=='rename' then query=''end
        local id=action=='create' and result.id or draft.id
        close_popup()
        local message=action=='delete'and L('status_deleted')or action=='create'and(L('status_saved_prefix')..(result.class_key==''and L('label_general')or L('label_class'))..': '..result.name)or L('status_saved')
        commit(updated,message,id)
    end
    local function action(id)
        if id=='wh3ep_lib_save_class_label'then id='wh3ep_lib_save_class'elseif id=='wh3ep_lib_save_general_label'then id='wh3ep_lib_save_general'end
        if id=='wh3ep_lib_open' then
            if visible and apply_busy()then status(L('error_busy'));return end
            ModLog('[WH3EP] library_open_clicked')
            local target=panel_cqi()
            if target~=selected_cqi and adapter.apply then adapter.apply.cancel()end
            selected_cqi=target
            local reason='no_selection'
            if selected_cqi then current,reason=adapter.describe(selected_cqi)else current=nil end
            if not current then
                ModLog('[WH3EP] library_open_rejected='..tostring(reason))
                entry_caption(L('button_select_hero'),L('hint_select_character'));return
            end
            local parent=find_uicomponent(core:get_ui_root(),'character_details_panel')
            if not parent then return end
            make_layout(parent);reload();refresh_display();visible=true;frame:SetVisible(true);entry:SetVisible(false);render()
            if cm and cm.repeat_real_callback then
                cm:remove_real_callback('wh3ep_library_search')
                cm:repeat_real_callback(function()
                    if faulted or not visible or draft or apply_busy()then return end
                    guarded(function()
                        local value=controls.search_input:GetStateText()
                        if type(value)=='string'and #value<=512 then
                            local original=value;local count=64
                            value=prefix(value,count)
                            local limit=(414-54-4)*0.85
                            while #value>0 and controls.search_input:WidthOfTextLine(value)>limit do count=count-1;value=prefix(original,count)end
                            if value~=original then text(controls.search_input,value)end
                            if value~=query then query,page,selected_id=value,1,nil;render()end
                        end
                    end)
                end,200,'wh3ep_library_search')
            end
            ModLog('[WH3EP] library_panel_ready')
            if apply_busy()and apply_report then on_apply_update(apply_report);return end
            status((library_status=='new' or library_status=='ok') and L('hint_save_scope') or explain(library_status))
            return
        end
        if id=='wh3ep_progress_verify'then id='wh3ep_lib_apply'elseif id=='wh3ep_progress_stop'then id='wh3ep_lib_close'end
        if not visible or not current then return end
        if id=='wh3ep_lib_close' then close();start_entry_tracking();return end
        if not selected_cqi or panel_cqi()~=selected_cqi then close();entry_caption(L('library_presets'),L('hint_character_changed'));return end
        if id=='wh3ep_lib_help'then controls.help:SetTooltipText(L('help_library'),true);return end
        if apply_busy()then
            if id=='wh3ep_lib_apply'and adapter.apply.waiting()then adapter.apply.resume()
            else status(L('error_finish_or_stop'))end
            return
        end
        if id=='wh3ep_lib_apply'then
            local preset=chosen()
            if not preset then status(L('select_loadout'));return end
            if not adapter.apply then status(L('error_apply_unavailable'));return end
            local plan,code=adapter.apply.preview(selected_cqi,preset,take)
            if not plan then status(explain(code));return end
            open_popup('apply',L('preview_title'),'',{plan=plan,preset=preset,page=1})
            return
        end
        if id=='wh3ep_lib_filter' then
            if filter_menu_open then close_filter_menu();return end
            filter_menu_open=not filter_menu_open
            controls.filter_menu:SetVisible(true)
            controls.filter_menu:RegisterTopMost()
            for _,key in ipairs(filters)do
                local option=controls['filter_option_'..key]
                set_base(option,key==filter and 'selected'or 'active')
                text(option,filter_names[key])
                option:SetVisible(filter_menu_open)
            end
            return
        end
        local filter_choice=id:match('^wh3ep_lib_filter_option_([a-z]+)$')
        if filter_choice and filter_names[filter_choice]then
            if not filter_menu_open then return end
            filter=filter_choice
            page,selected_id=1,nil
            render();return
        end
        if id=='wh3ep_lib_previous' then if page<=1 then return end;page=page-1;selected_id=nil;render();return end
        if id=='wh3ep_lib_next' then if page>=library_pages then return end;page=page+1;selected_id=nil;render();return end
        if id=='wh3ep_lib_search'or id=='wh3ep_lib_clear_search'then
            local value=id=='wh3ep_lib_clear_search'and ''or controls.search_input:GetStateText()
            if type(value)~='string'or #value>512 then status(explain('invalid_name'));return end
            query,page,selected_id=value,1,nil;render();return
        end
        local star=tonumber(id:match('^row_star_(%d+)$'))
        local row=tonumber(id:match('^wh3ep_lib_row_(%d+)$'))or star
        if row then
            diagnostic_stage='list'
        local list=library and model.list(library,current.faction_key,current.class_key,filter,query,current.character_kind) or {}
            local preset=list and list[(page-1)*page_size+row]
            if preset then
                if star then
                    if not writable()then return end
                    local updated,code=model.update(library,current.faction_key,preset.id,{favorite=not preset.favorite})
                    if updated then commit(updated,L('status_favorites'),preset.id)else status(explain(code))end
                else selected_id=preset.id;render()end
            end
            return
        end
        if id=='wh3ep_lib_delete' and library_status=='backup_available' then open_popup('restore',L('restore_title'),'yes');return end
        if not writable()then return end
        if id=='wh3ep_lib_save_class'or id=='wh3ep_lib_save_general'then save_scope=id=='wh3ep_lib_save_class'and 'class'or 'general';render();return end
        if id=='wh3ep_lib_save'then
            local snapshot,code=adapter.capture(selected_cqi)
            if not snapshot then status(explain(code));return end
            open_popup('create',L('create_title'),'',{snapshot=snapshot,class_key=save_scope=='general'and ''or current.class_key})
            return
        end
        local preset=chosen()
        if not preset then status(L('select_loadout'));return end
        if id=='wh3ep_lib_favorite' then
            local updated,code=model.update(library,current.faction_key,preset.id,{favorite=not preset.favorite})
            if updated then commit(updated,L('status_favorites'),preset.id)else status(explain(code))end
        elseif id=='wh3ep_lib_change_scope' then
            local updated,code=model.update(library,current.faction_key,preset.id,{class_key=preset.class_key=='' and current.class_key or '',character_kind=current.character_kind})
            if updated then filter='matching';commit(updated,L('status_scope'),preset.id)else status(explain(code))end
        elseif id=='wh3ep_lib_rename' then open_popup('rename',L('rename_title'),preset.name,{id=preset.id,icon_key=preset.icon_key or 'general'})
        elseif id=='wh3ep_lib_delete' then open_popup('delete',L('delete_title'),preset.name,{id=preset.id})
        elseif id=='wh3ep_lib_overwrite' then
            if preset.class_key~='' and (preset.class_key~=current.class_key or preset.character_kind~=current.character_kind) then status(L('error_scope_character'));return end
            local snapshot,code=adapter.capture(selected_cqi)
            if snapshot then open_popup('overwrite',L('overwrite_title'),preset.name,{id=preset.id,snapshot=snapshot})else status(explain(code))end
        end
    end
    local function row_hit(component_id)
        return component_id:match('^row_name_(%d+)$')or component_id:match('^row_meta_(%d+)$')or component_id:match('^row_icon_(%d+)$')or component_id:match('^row_frame_(%d+)$')
    end
    local function hover(context,on)
        if not visible or not frame then return end
        local component=UIComponent(context.component)
        if draft and not uicomponent_descended_from(component,'wh3ep_lib_input_popup')then return end
        local component_id=component:Id()
        local icon_key=component_id:match('^preset_icon_art_([%a_]+)$')or component_id:match('^preset_icon_label_([%a_]+)$')
        local index=row_hit(component_id)
        local id=icon_key and ('preset_icon_option_'..icon_key)or index and ('wh3ep_lib_row_'..index)or component_id
        local target=(draft and find_uicomponent(popup,id))or find_uicomponent(frame,id)
        local state=target and base_states[id]
        if not state or state=='inactive'then return end
        hovered_id=on and id or nil
        local native_state=target:CurrentState()
        if native_state=='down'or native_state=='down_off'or native_state=='selected_down'or native_state=='selected_down_off'then return end
        checked_state(target,on and (state=='selected'and 'selected_hover'or 'hover')or state)
        if id=='wh3ep_lib_search'then ModLog('[WH3EP] ui_find_hover='..tostring(on)..';state='..target:CurrentState())end
    end
    function U.start()
        if started then return end;started=true
        core:add_listener('wh3ep_lib_mouse_on','ComponentMouseOn',true,function(context)guarded(function()hover(context,true)end)end,true)
        core:add_listener('wh3ep_lib_mouse_off','ComponentMouseOff',true,function(context)guarded(function()hover(context,false)end)end,true)
        core:add_listener('wh3ep_lib_selected','CharacterSelected',true,function(context)
            guarded(function()
                ModLog('[WH3EP] selection_stage=context')
                local character=context:character()
                local next_cqi=character and character:command_queue_index()or nil
                if next_cqi~=selected_cqi and adapter.apply then adapter.apply.cancel()end
                selected_cqi=next_cqi
                ModLog('[WH3EP] selection_stage=describe')
                current=selected_cqi and adapter.describe(selected_cqi)or nil
                ModLog('[WH3EP] selection_stage=described')
                if visible then ModLog('[WH3EP] selection_stage=inspect');refresh_display();ModLog('[WH3EP] selection_stage=inspected')end
                ModLog('[WH3EP] library_selection_ready='..tostring(current~=nil))
                if draft then close_popup()end
                if visible then if current then render()else close()end end
                start_entry_tracking()
            end)
        end,true)
        core:add_listener('wh3ep_lib_panel_open','PanelOpenedCampaign',function(context)return context.string=='character_details_panel'end,function()
            entry_panel_open=true
            if faulted then
                if adapter.apply and adapter.apply.waiting()then pcall(show_recovery_entry)end
                return
            end
            guarded(function()
                local parent=find_uicomponent(core:get_ui_root(),'character_details_panel')
                if not parent then return end
                entry=core:get_or_create_component('wh3ep_lib_open','ui/templates/wh3ep_entry.twui.xml',parent)
                entry:PropagatePriority(151);entry:Resize(184,46);label_sizes[entry:Id()]={184,46};report_events(entry);place_entry(parent)
                button_ids.wh3ep_lib_open=true
                entry_caption(L('library_presets'),L('hint_open_library'))
                if visible then entry:SetVisible(false)end
                ModLog('[WH3EP] library_button_ready')
                ModLog('[WH3EP] library_entry_state='..tostring(entry:CurrentState()))
                ModLog('[WH3EP] library_entry_interactive='..tostring(entry:IsInteractive()))
                ModLog('[WH3EP] library_entry_priority='..tostring(entry:Priority()))
                start_entry_tracking()
            end)
        end,true)
        core:add_listener('wh3ep_lib_panel_close','PanelClosedCampaign',function(context)return context.string=='character_details_panel'end,function()
            entry_panel_open=false;stop_entry_tracking()
            pcall(function()if entry then entry:SetVisible(false)end end)
            guarded(function()close();frame,popup,entry,progress=nil,nil,nil,nil;card_slots=12;controls,rows,button_ids={},{},{};base_states,hovered_id={},nil;reporters={} end)
        end,true)
        core:add_listener('wh3ep_lib_click','ComponentLClickUp',true,function(context)
            if faulted then faulted_verification(context);return end
            guarded(function()
                local component=UIComponent(context.component)
                local component_id=component:Id()
                if entry then
                    local hit=type(component_id)=='string'and #component_id<=96 and component_id:match('^[%w_%-]+$')and component_id or 'unmapped'
                    ModLog('[WH3EP] library_hit='..hit)
                end
                if draft then
                    if not uicomponent_descended_from(component,'wh3ep_lib_input_popup')then return end
                    if not selected_cqi or panel_cqi()~=selected_cqi then close();entry_caption(L('library_presets'),L('hint_character_changed'));return end
                    if draft.action=='create'or draft.action=='rename'then
                        local icon_key=component_id:match('^preset_icon_option_([%a_]+)$')or component_id:match('^preset_icon_art_([%a_]+)$')or component_id:match('^preset_icon_label_([%a_]+)$')
                        if icon_key and preset_icons[icon_key]then
                            draft.icon_key=icon_key
                            for _,key in ipairs(model.preset_icon_keys())do set_base(find_uicomponent(popup,'preset_icon_option_'..key),key==icon_key and 'selected'or 'active')end
                            return
                        end
                    end
                    if draft.action=='apply'and (component_id=='button_preview_take'or component_id=='preview_take_label'or uicomponent_descended_from(component,'button_preview_take'))then
                        local plan,code=adapter.apply.preview(selected_cqi,draft.preset,not take)
                        if plan then take=not take;draft.plan=plan;render_apply_preview();apply_buttons()else status(explain(code))end
                        return
                    end
                    if draft.action=='apply'and (component_id=='button_preview_previous'or component_id=='button_preview_next')then
                        draft.page=draft.page+(component_id=='button_preview_next'and 1 or -1);render_apply_preview();return
                    end
                    if draft.action=='apply'and uicomponent_descended_from(component,'button_preview_previous')then draft.page=draft.page-1;render_apply_preview();return end
                    if draft.action=='apply'and uicomponent_descended_from(component,'button_preview_next')then draft.page=draft.page+1;render_apply_preview();return end
                    if component_id=='button_preview_close'then if draft.action=='result'then accept_popup()else close_popup()end;return end
                    if component_id=='button_preview_help'then find_uicomponent(popup,'button_preview_help'):SetTooltipText(draft.action=='result'and L('help_result')or L('help_preview'),true);return end
                    if component_id=='button_cancel'or uicomponent_descended_from(component,'button_cancel')then close_popup();return end
                    if component_id=='button_ok'or uicomponent_descended_from(component,'button_ok')then accept_popup();return end
                    return
                end
                local row_hit=row_hit(component_id)
                local id=row_hit and ('wh3ep_lib_row_'..row_hit)or button_ids[component_id]and component_id or nil
                if not id then
                    for button_id in pairs(button_ids)do
                        if uicomponent_descended_from(component,button_id)then id=button_id;break end
                    end
                end
                if id then
                    if id~='wh3ep_lib_filter'and not id:match('^wh3ep_lib_filter_option_')then close_filter_menu()end
                    ModLog('[WH3EP] library_route='..id)
                    ModLog('[WH3EP] library_event_id_matches='..tostring(context.string==component_id))
                    action(id)
                elseif filter_menu_open then
                    close_filter_menu()
                end
            end)
        end,true)
    end
    return U
end
