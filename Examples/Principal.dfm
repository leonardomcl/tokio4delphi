object FPrincipal: TFPrincipal
  Left = 0
  Top = 0
  BorderIcons = [biSystemMenu, biMinimize]
  BorderStyle = bsSingle
  Caption = 'Tokio4Delphi - Examples'
  ClientHeight = 488
  ClientWidth = 931
  Color = clWhite
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -16
  Font.Name = 'Consolas'
  Font.Style = []
  Position = poScreenCenter
  RoundedCorners = rcOn
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  TextHeight = 19
  object Label1: TLabel
    AlignWithMargins = True
    Left = 3
    Top = 234
    Width = 925
    Height = 19
    Align = alBottom
    Caption = '...'
    ExplicitLeft = 0
    ExplicitTop = 225
    ExplicitWidth = 27
  end
  object MLog: TMemo
    AlignWithMargins = True
    Left = 3
    Top = 298
    Width = 925
    Height = 186
    Margins.Top = 10
    Margins.Bottom = 4
    Align = alBottom
    BevelInner = bvNone
    BevelOuter = bvNone
    BorderStyle = bsNone
    Color = clNavy
    EditMargins.Left = 4
    EditMargins.Right = 4
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clYellow
    Font.Height = -11
    Font.Name = 'Consolas'
    Font.Style = []
    ParentFont = False
    PopupMenu = PopupMenu1
    ScrollBars = ssVertical
    TabOrder = 0
    ExplicitTop = 263
    ExplicitWidth = 919
  end
  object ProgressBar1: TProgressBar
    AlignWithMargins = True
    Left = 3
    Top = 259
    Width = 925
    Height = 26
    Align = alBottom
    Smooth = True
    TabOrder = 1
    ExplicitLeft = 0
    ExplicitTop = 227
  end
  object PageControl1: TPageControl
    AlignWithMargins = True
    Left = 3
    Top = 3
    Width = 925
    Height = 142
    ActivePage = TabSheet1
    Align = alTop
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -15
    Font.Name = 'Consolas'
    Font.Style = []
    ParentFont = False
    TabOrder = 2
    ExplicitWidth = 919
    object TabSheet1: TTabSheet
      BorderWidth = 10
      Caption = 'Principal'
      object FlowPanel1: TFlowPanel
        AlignWithMargins = True
        Left = 3
        Top = 3
        Width = 891
        Height = 83
        Align = alClient
        BevelOuter = bvNone
        Color = clWhite
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clWindowText
        Font.Height = -11
        Font.Name = 'Consolas'
        Font.Style = []
        Padding.Left = 16
        Padding.Top = 16
        Padding.Right = 16
        Padding.Bottom = 16
        ParentBackground = False
        ParentFont = False
        TabOrder = 0
        object BtnAwait: TButton
          AlignWithMargins = True
          Left = 19
          Top = 19
          Width = 108
          Height = 30
          Caption = 'AWAIT'
          Font.Charset = DEFAULT_CHARSET
          Font.Color = clWindowText
          Font.Height = -11
          Font.Name = 'Consolas'
          Font.Style = []
          ParentFont = False
          TabOrder = 0
          OnClick = BtnAwaitClick
        end
        object BtnAsync: TButton
          AlignWithMargins = True
          Left = 133
          Top = 19
          Width = 108
          Height = 30
          Caption = 'ASYNC'
          Font.Charset = DEFAULT_CHARSET
          Font.Color = clWindowText
          Font.Height = -11
          Font.Name = 'Consolas'
          Font.Style = []
          ParentFont = False
          TabOrder = 1
          OnClick = BtnAsyncClick
        end
        object BtnRetryAsync: TButton
          AlignWithMargins = True
          Left = 247
          Top = 19
          Width = 108
          Height = 30
          Caption = 'RETRY ASYNC'
          Font.Charset = DEFAULT_CHARSET
          Font.Color = clWindowText
          Font.Height = -11
          Font.Name = 'Consolas'
          Font.Style = []
          ParentFont = False
          TabOrder = 2
          OnClick = BtnRetryAsyncClick
        end
        object BtnAll: TButton
          AlignWithMargins = True
          Left = 361
          Top = 19
          Width = 108
          Height = 30
          Caption = 'ALL'
          Font.Charset = DEFAULT_CHARSET
          Font.Color = clWindowText
          Font.Height = -11
          Font.Name = 'Consolas'
          Font.Style = []
          ParentFont = False
          TabOrder = 3
          OnClick = BtnAllClick
        end
        object BtnAllAsync: TButton
          AlignWithMargins = True
          Left = 475
          Top = 19
          Width = 108
          Height = 30
          Caption = 'ALL ASYNC'
          Font.Charset = DEFAULT_CHARSET
          Font.Color = clWindowText
          Font.Height = -11
          Font.Name = 'Consolas'
          Font.Style = []
          ParentFont = False
          TabOrder = 4
          OnClick = BtnAllAsyncClick
        end
        object BtnRace: TButton
          AlignWithMargins = True
          Left = 589
          Top = 19
          Width = 108
          Height = 30
          Caption = 'RACE'
          Font.Charset = DEFAULT_CHARSET
          Font.Color = clWindowText
          Font.Height = -11
          Font.Name = 'Consolas'
          Font.Style = []
          ParentFont = False
          TabOrder = 5
          OnClick = BtnRaceClick
        end
        object BtnRaceAsync: TButton
          AlignWithMargins = True
          Left = 703
          Top = 19
          Width = 108
          Height = 30
          Caption = 'RACE ASYNC'
          Font.Charset = DEFAULT_CHARSET
          Font.Color = clWindowText
          Font.Height = -11
          Font.Name = 'Consolas'
          Font.Style = []
          ParentFont = False
          TabOrder = 6
          OnClick = BtnRaceAsyncClick
        end
        object BtnDelayAsync: TButton
          AlignWithMargins = True
          Left = 19
          Top = 55
          Width = 108
          Height = 30
          Caption = 'DELAY ASYNC'
          Font.Charset = DEFAULT_CHARSET
          Font.Color = clWindowText
          Font.Height = -11
          Font.Name = 'Consolas'
          Font.Style = []
          ParentFont = False
          TabOrder = 7
          OnClick = BtnDelayAsyncClick
        end
        object BtnWithTimeout: TButton
          AlignWithMargins = True
          Left = 133
          Top = 55
          Width = 108
          Height = 30
          Caption = 'WITH TIMEOUT'
          Font.Charset = DEFAULT_CHARSET
          Font.Color = clWindowText
          Font.Height = -11
          Font.Name = 'Consolas'
          Font.Style = []
          ParentFont = False
          TabOrder = 8
          OnClick = BtnWithTimeoutClick
        end
        object BtnWhenAllComplete: TButton
          AlignWithMargins = True
          Left = 247
          Top = 55
          Width = 108
          Height = 30
          Caption = 'WHEN ALL COMPLETE'
          Font.Charset = DEFAULT_CHARSET
          Font.Color = clWindowText
          Font.Height = -11
          Font.Name = 'Consolas'
          Font.Style = []
          ParentFont = False
          TabOrder = 9
          OnClick = BtnWhenAllCompleteClick
        end
        object BtnParallel: TButton
          AlignWithMargins = True
          Left = 361
          Top = 55
          Width = 108
          Height = 30
          Caption = 'PARALLEL FOR'
          Font.Charset = DEFAULT_CHARSET
          Font.Color = clWindowText
          Font.Height = -11
          Font.Name = 'Consolas'
          Font.Style = []
          ParentFont = False
          TabOrder = 10
          OnClick = BtnParallelClick
        end
        object BtnRunWithProgress: TButton
          AlignWithMargins = True
          Left = 475
          Top = 55
          Width = 130
          Height = 30
          Caption = 'RUN WITH PROGRESS'
          Font.Charset = DEFAULT_CHARSET
          Font.Color = clWindowText
          Font.Height = -11
          Font.Name = 'Consolas'
          Font.Style = []
          ParentFont = False
          TabOrder = 11
          OnClick = BtnRunWithProgressClick
        end
        object BtnSeries: TButton
          AlignWithMargins = True
          Left = 611
          Top = 55
          Width = 106
          Height = 30
          Caption = 'SERIES'
          Font.Charset = DEFAULT_CHARSET
          Font.Color = clWindowText
          Font.Height = -11
          Font.Name = 'Consolas'
          Font.Style = []
          ParentFont = False
          TabOrder = 12
          OnClick = BtnSeriesClick
        end
        object BtnSeriesAsync: TButton
          AlignWithMargins = True
          Left = 723
          Top = 55
          Width = 106
          Height = 30
          Caption = 'SERIES ASYNC'
          Font.Charset = DEFAULT_CHARSET
          Font.Color = clWindowText
          Font.Height = -11
          Font.Name = 'Consolas'
          Font.Style = []
          ParentFont = False
          TabOrder = 13
          OnClick = BtnSeriesAsyncClick
        end
      end
    end
    object TabSheet2: TTabSheet
      BorderWidth = 10
      Caption = 'Uses Examples'
      ImageIndex = 1
      object FlowPanel2: TFlowPanel
        AlignWithMargins = True
        Left = 3
        Top = 3
        Width = 891
        Height = 87
        Align = alClient
        BevelOuter = bvNone
        Color = clWhite
        Padding.Left = 16
        Padding.Top = 16
        Padding.Right = 16
        Padding.Bottom = 16
        ParentBackground = False
        TabOrder = 0
        ExplicitWidth = 885
        ExplicitHeight = 83
        object btnFetchAll: TButton
          AlignWithMargins = True
          Left = 19
          Top = 19
          Width = 121
          Height = 30
          Caption = 'FETCH ALL'
          Font.Charset = DEFAULT_CHARSET
          Font.Color = clWindowText
          Font.Height = -11
          Font.Name = 'Consolas'
          Font.Style = []
          ParentFont = False
          TabOrder = 0
          OnClick = btnFetchAllClick
        end
        object BtnFindId: TButton
          AlignWithMargins = True
          Left = 146
          Top = 19
          Width = 220
          Height = 30
          Caption = 'GET RANDOM MID ID FROM LIST'
          Font.Charset = DEFAULT_CHARSET
          Font.Color = clWindowText
          Font.Height = -11
          Font.Name = 'Consolas'
          Font.Style = []
          ParentFont = False
          TabOrder = 1
          OnClick = BtnFindIdClick
        end
        object BtnFindRandomId: TButton
          AlignWithMargins = True
          Left = 372
          Top = 19
          Width = 220
          Height = 30
          Caption = 'GET RANDOM ID FROM LIST'
          Font.Charset = DEFAULT_CHARSET
          Font.Color = clWindowText
          Font.Height = -11
          Font.Name = 'Consolas'
          Font.Style = []
          ParentFont = False
          TabOrder = 2
          OnClick = BtnFindRandomIdClick
        end
        object btnProcess: TButton
          AlignWithMargins = True
          Left = 598
          Top = 19
          Width = 140
          Height = 30
          Caption = 'DOWNLOAD/UNZIP/DELETE'
          Font.Charset = DEFAULT_CHARSET
          Font.Color = clWindowText
          Font.Height = -11
          Font.Name = 'Consolas'
          Font.Style = []
          ParentFont = False
          TabOrder = 3
          OnClick = btnProcessClick
        end
        object BtnLoadDashboard: TButton
          AlignWithMargins = True
          Left = 744
          Top = 19
          Width = 99
          Height = 30
          Caption = 'LOAD DASHBOARD'
          Font.Charset = DEFAULT_CHARSET
          Font.Color = clWindowText
          Font.Height = -11
          Font.Name = 'Consolas'
          Font.Style = []
          ParentFont = False
          TabOrder = 4
          OnClick = BtnLoadDashboardClick
        end
      end
    end
  end
  object GroupBox1: TGroupBox
    AlignWithMargins = True
    Left = 3
    Top = 151
    Width = 925
    Height = 77
    Align = alClient
    Caption = 'Cancel Taks'
    DefaultHeaderFont = False
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clWindowText
    Font.Height = -16
    Font.Name = 'Consolas'
    Font.Style = [fsBold]
    HeaderFont.Charset = DEFAULT_CHARSET
    HeaderFont.Color = clWindowText
    HeaderFont.Height = -18
    HeaderFont.Name = 'Consolas'
    HeaderFont.Style = []
    ParentFont = False
    TabOrder = 3
    ExplicitWidth = 919
    ExplicitHeight = 54
    object BtnStrVarTasks: TButton
      AlignWithMargins = True
      Left = 16
      Top = 24
      Width = 225
      Height = 38
      Caption = 'Start Various Tasks'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -11
      Font.Name = 'Consolas'
      Font.Style = []
      ParentFont = False
      TabOrder = 0
      OnClick = BtnStrVarTasksClick
    end
    object BtnStopVrsTasks: TButton
      AlignWithMargins = True
      Left = 247
      Top = 24
      Width = 225
      Height = 38
      Caption = 'Cancel Various Tasks'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -11
      Font.Name = 'Consolas'
      Font.Style = []
      ParentFont = False
      TabOrder = 1
      OnClick = BtnStopVrsTasksClick
    end
    object EdtId: TEdit
      Left = 669
      Top = 24
      Width = 98
      Height = 30
      Alignment = taCenter
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -19
      Font.Name = 'Consolas'
      Font.Style = [fsBold]
      NumbersOnly = True
      ParentFont = False
      TabOrder = 2
      Text = '651'
      TextHint = 'ID'
    end
    object Button3: TButton
      Left = 527
      Top = 24
      Width = 136
      Height = 38
      Caption = 'CREATE TASK BY ID'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -11
      Font.Name = 'Consolas'
      Font.Style = []
      ParentFont = False
      TabOrder = 3
      OnClick = Button3Click
    end
    object Button4: TButton
      Left = 772
      Top = 24
      Width = 136
      Height = 38
      Caption = 'CANCEL BY ID'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -11
      Font.Name = 'Consolas'
      Font.Style = []
      ParentFont = False
      TabOrder = 4
      OnClick = Button4Click
    end
  end
  object PopupMenu1: TPopupMenu
    Left = 280
    Top = 368
    object CLEAR1: TMenuItem
      Caption = 'CLEAR'
      OnClick = CLEAR1Click
    end
  end
end
